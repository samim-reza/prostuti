import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/features/chat/data/chat_repository.dart';
import 'package:prostuti/features/feed/application/post_events.dart';
import 'package:prostuti/features/friends/application/friends_controller.dart';
import 'package:prostuti/features/friends/data/friends_repository.dart';
import 'package:prostuti/features/friends/data/relationship.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';

/// Relationships already known from list payloads (friends list, requests,
/// suggestions, batched search lookups). Lets a [RelationshipNotifier] start
/// with the right button instantly instead of calling `get_relationship`.
/// Bounded LRU so a long session can't grow it forever.
class RelationshipSeeds {
  RelationshipSeeds({this.capacity = 500});

  final int capacity;
  final _map = <String, Relationship>{};

  Relationship? operator [](String userId) {
    final value = _map.remove(userId);
    if (value != null) _map[userId] = value;
    return value;
  }

  void put(String userId, Relationship relationship) {
    _map
      ..remove(userId)
      ..[userId] = relationship;
    while (_map.length > capacity) {
      _map.remove(_map.keys.first);
    }
  }

  void putAll(Map<String, Relationship> entries) => entries.forEach(put);

  void clear() => _map.clear();
}

final relationshipSeedsProvider = Provider<RelationshipSeeds>((ref) {
  ref.watch(currentUserIdProvider);
  return RelationshipSeeds();
});

/// The relationship between me and one user, with optimistic actions.
/// Every action flips the state immediately and rolls back on failure.
class RelationshipNotifier extends AsyncNotifier<Relationship> {
  RelationshipNotifier(this.userId);

  final String userId;

  FriendsRepository get _repo => ref.read(friendsRepositoryProvider);
  RelationshipSeeds get _seeds => ref.read(relationshipSeedsProvider);

  @override
  FutureOr<Relationship> build() {
    final me = ref.watch(currentUserIdProvider);
    if (me == userId) return Relationship.self;
    final seeded = _seeds[userId];
    if (seeded != null) return seeded;
    return _fetch();
  }

  Future<Relationship> _fetch() async {
    final r = await _repo.relationship(userId);
    _seeds.put(userId, r);
    return r;
  }

  Relationship get _current => state.value ?? Relationship.none;

  Future<void> reload() async {
    final r = await _fetch();
    if (ref.mounted) state = AsyncData(r);
  }

  Future<void> sendRequest() =>
      _mutate(const Relationship(RelationshipStatus.requestSent), () => _repo.sendRequest(userId));

  Future<void> cancelRequest() async {
    final id = _current.requestId;
    if (id == null) return reload();
    return _mutate(Relationship.none, () async {
      await _repo.cancelRequest(id);
      return Relationship.none;
    });
  }

  /// Works offline (queued).
  Future<void> accept() async {
    final id = _current.requestId;
    if (id == null) return reload();
    return _mutate(Relationship.friends, () => _repo.respondOrQueue(id, userId: userId, accept: true));
  }

  /// Works offline (queued).
  Future<void> decline() async {
    final id = _current.requestId;
    if (id == null) return reload();
    return _mutate(Relationship.none, () => _repo.respondOrQueue(id, userId: userId, accept: false));
  }

  Future<void> unfriend() => _mutate(Relationship.none, () async {
    await _repo.unfriend(userId);
    return Relationship.none;
  });

  Future<void> block() => _mutate(Relationship.blocked, () async {
    await _repo.block(userId);
    return Relationship.blocked;
  });

  Future<void> unblock() => _mutate(Relationship.none, () async {
    await _repo.unblock(userId);
    return Relationship.none;
  });

  Future<void> _mutate(Relationship optimistic, Future<Relationship> Function() call) async {
    final previous = _current;
    _set(optimistic);
    try {
      final result = await call();
      _set(result);
      _afterChange(previous, result);
    } on Object {
      _set(previous);
      rethrow;
    }
  }

  void _set(Relationship r) {
    // Seeds are app-scoped, so the latest answer survives even if this
    // auto-disposed notifier is gone by the time the request completes; the
    // persisted copy keeps the profile button right offline.
    _seeds.put(userId, r);
    unawaited(_repo.rememberRelationship(userId, r));
    if (ref.mounted) state = AsyncData(r);
  }

  /// Side effects on other screens (badges, lists, counters, feeds).
  void _afterChange(Relationship before, Relationship after) {
    if (!ref.mounted) return;
    applyRelationshipSideEffects(ref, userId, before, after);
  }
}

final relationshipProvider = AsyncNotifierProvider.autoDispose.family<RelationshipNotifier, Relationship, String>(
  RelationshipNotifier.new,
);

/// Keeps badges, friend lists, profile counters and feeds consistent after
/// a relationship change.
void applyRelationshipSideEffects(Ref ref, String userId, Relationship before, Relationship after) {
  if (before.status == RelationshipStatus.requestReceived) ref.invalidate(incomingRequestCountProvider);
  if (before.isFriend != after.isFriend) {
    if (ref.exists(friendsListProvider)) unawaited(ref.read(friendsListProvider.notifier).refresh());
    unawaited(ref.read(chatRepositoryProvider).invalidateFriends());
    final profiles = ref.read(profileRepositoryProvider);
    final me = ref.read(currentUserIdProvider);
    unawaited(profiles.invalidate(userId));
    ref.invalidate(profileByIdProvider(userId));
    if (me != null) {
      unawaited(profiles.invalidate(me));
      ref.invalidate(profileByIdProvider(me));
      unawaited(ref.read(currentProfileProvider.notifier).reload().catchError((Object _) {}));
    }
  }
  if (before.status == RelationshipStatus.none || after.status == RelationshipStatus.none) {
    unawaited(ref.read(friendsRepositoryProvider).invalidateSuggestions());
  }
  if (after.isBlocked) ref.read(postEventsProvider.notifier).emit(AuthorHidden(userId));
  if (before.isBlocked && !after.isBlocked) ref.read(postEventsProvider.notifier).emit(AuthorUnblocked(userId));
}
