import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/pagination/paged_notifier.dart';
import 'package:prostuti/core/pagination/paged_state.dart';
import 'package:prostuti/core/rate_limit/debouncer.dart';
import 'package:prostuti/features/friends/application/relationship_controller.dart';
import 'package:prostuti/features/friends/data/friend_models.dart';
import 'package:prostuti/features/friends/data/friends_repository.dart';
import 'package:prostuti/features/friends/data/relationship.dart';

PageResult<T, DateTime> _timePage<T>(List<T> items, DateTime Function(T item) cursorOf) =>
    PageResult(items, items.isEmpty || items.length < FriendsRepository.pageSize ? null : cursorOf(items.last));

/// My friends, newest friendship first (keyset on `friends_since`).
class FriendsListNotifier extends PagedNotifier<Friend, DateTime> {
  @override
  PagedState<Friend, DateTime> build() {
    ref.watch(currentUserIdProvider);
    return super.build();
  }

  @override
  Future<PageResult<Friend, DateTime>> fetchPage(DateTime? cursor) async {
    final items = await ref.read(friendsRepositoryProvider).fetchFriends(before: cursor);
    _seed(items);
    return _timePage(items, (f) => f.friendsSince);
  }

  @override
  List<Friend>? readCachedFirstPage() {
    final cached = ref.read(friendsRepositoryProvider).readCachedFriends();
    if (cached != null) _seed(cached);
    return cached;
  }

  void _seed(List<Friend> items) {
    final seeds = ref.read(relationshipSeedsProvider);
    for (final f in items) {
      // Don't clobber a fresher local answer (e.g. an unfriend just made).
      if (seeds[f.user.id] == null) seeds.put(f.user.id, Relationship.friends);
    }
  }

  @override
  Object idOf(Friend item) => item.user.id;
}

final friendsListProvider = NotifierProvider.autoDispose<FriendsListNotifier, PagedState<Friend, DateTime>>(
  FriendsListNotifier.new,
);

/// Pending requests: incoming (`true`) or sent by me (`false`).
class FriendRequestsNotifier extends PagedNotifier<FriendRequest, DateTime> {
  FriendRequestsNotifier(this.incoming);

  final bool incoming;

  @override
  Future<PageResult<FriendRequest, DateTime>> fetchPage(DateTime? cursor) async {
    final items = await ref.read(friendsRepositoryProvider).fetchRequests(incoming: incoming, before: cursor);
    _seed(items);
    return _timePage(items, (r) => r.createdAt);
  }

  @override
  List<FriendRequest>? readCachedFirstPage() {
    final cached = ref.read(friendsRepositoryProvider).readCachedRequests(incoming: incoming);
    if (cached != null) _seed(cached);
    return cached;
  }

  /// Seeds each row's button; answers still queued offline win, so an
  /// accepted request keeps showing "Friends" after a restart.
  void _seed(List<FriendRequest> items) {
    final status = incoming ? RelationshipStatus.requestReceived : RelationshipStatus.requestSent;
    final queued = incoming ? ref.read(friendsRepositoryProvider).pendingResponses() : const <String, bool>{};
    ref.read(relationshipSeedsProvider).putAll({
      for (final r in items)
        r.user.id: switch (queued[r.user.id]) {
          true => Relationship.friends,
          false => Relationship.none,
          null => Relationship(status, requestId: r.id),
        },
    });
  }

  @override
  Object idOf(FriendRequest item) => item.id;
}

final friendRequestsProvider = NotifierProvider.autoDispose
    .family<FriendRequestsNotifier, PagedState<FriendRequest, DateTime>, bool>(FriendRequestsNotifier.new);

/// Badge: number of pending incoming requests.
final incomingRequestCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(friendsRepositoryProvider).incomingRequestCount(),
);

/// "People you may know", with local dismissals.
class SuggestionsNotifier extends AsyncNotifier<List<FriendSuggestion>> {
  final _dismissed = <String>{};

  @override
  Future<List<FriendSuggestion>> build() async {
    ref.watch(currentUserIdProvider);
    return _load();
  }

  Future<List<FriendSuggestion>> _load({bool force = false}) async {
    final list = await ref.read(friendsRepositoryProvider).fetchSuggestions(force: force);
    final seeds = ref.read(relationshipSeedsProvider);
    for (final s in list) {
      // Cached suggestions may be stale; never overwrite a fresher answer.
      if (seeds[s.user.id] == null) seeds.put(s.user.id, Relationship.none);
    }
    return list.where((s) => !_dismissed.contains(s.user.id)).toList(growable: false);
  }

  Future<void> refresh() async {
    final list = await _load(force: true);
    if (ref.mounted) state = AsyncData(list);
  }

  void dismiss(String userId) {
    _dismissed.add(userId);
    final current = state.value;
    if (current != null) state = AsyncData(current.where((s) => s.user.id != userId).toList(growable: false));
  }
}

final suggestionsProvider = AsyncNotifierProvider.autoDispose<SuggestionsNotifier, List<FriendSuggestion>>(
  SuggestionsNotifier.new,
);

// ---------------------------------------------------------------------------
// User search
// ---------------------------------------------------------------------------

@immutable
class UserSearchState {
  const UserSearchState({this.query = '', this.results = const AsyncData([])});

  final String query;
  final AsyncValue<List<UserSearchResult>> results;

  static const minLength = 2;

  bool get tooShort => query.trim().length < minLength;
}

/// Debounced (400 ms) user search. Out-of-order responses are discarded,
/// recent queries are served from a small LRU, and relationships for the
/// whole page are resolved in one batch so every row shows the right button.
class UserSearchNotifier extends Notifier<UserSearchState> {
  static const debounce = Duration(milliseconds: 400);
  static const _cacheSize = 20;

  final _debouncer = Debouncer(debounce);
  final _cache = <String, List<UserSearchResult>>{};
  int _generation = 0;

  @override
  UserSearchState build() {
    ref.onDispose(_debouncer.dispose);
    return const UserSearchState();
  }

  void onQueryChanged(String raw) {
    final query = raw.trim();
    final gen = ++_generation;
    if (query.length < UserSearchState.minLength) {
      _debouncer.dispose();
      state = UserSearchState(query: query);
      return;
    }
    final cached = _cache[query.toLowerCase()];
    if (cached != null) {
      _debouncer.dispose();
      state = UserSearchState(query: query, results: AsyncData(cached));
      return;
    }
    if (!ConnectivityService.instance.hasInterface) {
      // Search needs the network: say so right away instead of spinning.
      _debouncer.dispose();
      state = UserSearchState(query: query, results: const AsyncError(NetworkFailure(), StackTrace.empty));
      return;
    }
    state = UserSearchState(query: query, results: const AsyncLoading());
    _debouncer(() => unawaited(_run(query, gen)));
  }

  Future<void> retry() async {
    final query = state.query;
    if (query.length < UserSearchState.minLength) return;
    state = UserSearchState(query: query, results: const AsyncLoading());
    await _run(query, ++_generation);
  }

  Future<void> _run(String query, int gen) async {
    if (query.trim().length < UserSearchState.minLength) return;
    final repo = ref.read(friendsRepositoryProvider);
    try {
      final results = await repo.search(query);
      if (results.isNotEmpty) {
        try {
          final rels = await repo.relationshipsFor([for (final r in results) r.user.id]);
          if (!ref.mounted) return;
          ref.read(relationshipSeedsProvider).putAll(rels);
        } on Object {
          // Buttons fall back to per-user lookups.
        }
      }
      if (!ref.mounted || gen != _generation) return;
      _cache[query.toLowerCase()] = results;
      while (_cache.length > _cacheSize) {
        _cache.remove(_cache.keys.first);
      }
      state = UserSearchState(query: query, results: AsyncData(results));
    } on Object catch (e, st) {
      if (!ref.mounted || gen != _generation) return;
      state = UserSearchState(query: query, results: AsyncError(e, st));
    }
  }
}

final userSearchProvider = NotifierProvider.autoDispose<UserSearchNotifier, UserSearchState>(UserSearchNotifier.new);
