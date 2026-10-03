import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/pagination/paged_notifier.dart';
import 'package:prostuti/core/pagination/paged_state.dart';
import 'package:prostuti/core/rate_limit/debouncer.dart';
import 'package:prostuti/features/feed/application/post_events.dart';
import 'package:prostuti/features/feed/data/feed_repository.dart';
import 'package:prostuti/features/feed/data/post.dart';
import 'package:prostuti/features/feed/data/report.dart';
import 'package:prostuti/features/friends/application/relationship_controller.dart';
import 'package:prostuti/features/friends/data/friends_repository.dart';
import 'package:prostuti/features/friends/data/relationship.dart';

/// Shared behaviour of post lists: keyset paging, a persisted first page for
/// instant/offline paint, queued (offline) writes merged in, event sync, and
/// an automatic refresh when the connection comes back after a failure.
abstract class _PostListNotifier extends PagedNotifier<Post, Keyset> with PostListSync {
  final _persist = Debouncer(const Duration(seconds: 1));

  /// `null` for the main feed.
  String? get authorId;

  FeedRepository get repo => ref.read(feedRepositoryProvider);

  /// Queued posts belong in this list (the main feed, or my own profile).
  bool get showsMyPendingPosts => authorId == null || authorId == ref.read(currentUserIdProvider);

  @override
  PagedState<Post, Keyset> build() {
    listenToPostEvents();
    ref
      ..onDispose(_persist.dispose)
      ..listen<AsyncValue<bool>>(isOnlineProvider, (prev, next) {
        if (next.value == true && prev?.value != true && state.error != null) unawaited(refresh());
      });
    return super.build();
  }

  List<Post> _merge(List<Post> page) => mergePendingWrites(
    page,
    pendingPosts: showsMyPendingPosts ? repo.pendingPosts() : const [],
    reactions: repo.pendingReactions(),
  );

  @override
  Future<PageResult<Post, Keyset>> fetchPage(Keyset? cursor) async {
    final items = await repo.fetchFeed(before: cursor, authorId: authorId);
    final page = keysetPage(items, FeedRepository.pageSize, (p) => p.cursor);
    return cursor == null ? PageResult(_merge(items), page.nextCursor) : page;
  }

  @override
  Object idOf(Post item) => item.id;

  @override
  List<Post>? readCachedFirstPage() {
    final cached = repo.readCachedFirstPage(authorId: authorId);
    final merged = _merge(cached ?? const []);
    return merged.isEmpty ? null : merged;
  }

  @override
  void applyPostEvent(PostEvent event) {
    super.applyPostEvent(event);
    // Keep the offline snapshot in line with what the user sees.
    _persist(() => unawaited(repo.cacheFirstPage(state.items, authorId: authorId)));
  }
}

/// The community feed (newest first).
class FeedNotifier extends _PostListNotifier {
  @override
  String? get authorId => null;

  @override
  PagedState<Post, Keyset> build() {
    // A different account must never see the previous user's feed.
    ref.watch(currentUserIdProvider);
    return super.build();
  }
}

final feedProvider = NotifierProvider<FeedNotifier, PagedState<Post, Keyset>>(FeedNotifier.new);

/// One user's posts (profile screen).
class AuthorFeedNotifier extends _PostListNotifier {
  AuthorFeedNotifier(this.authorId);

  @override
  final String authorId;

  @override
  bool acceptsNewPost(Post post) => post.author.id == authorId;
}

final authorFeedProvider = NotifierProvider.autoDispose.family<AuthorFeedNotifier, PagedState<Post, Keyset>, String>(
  AuthorFeedNotifier.new,
);

/// A single post. Paints instantly from the feed (or the offline cache),
/// then revalidates; fresh counts are broadcast to every list.
class PostDetailNotifier extends AsyncNotifier<Post?> {
  PostDetailNotifier(this.postId);

  final String postId;

  FeedRepository get _repo => ref.read(feedRepositoryProvider);

  @override
  FutureOr<Post?> build() {
    ref.listen<PostEvent?>(postEventsProvider, (_, event) {
      final current = state.value;
      switch (event) {
        case PostChanged(:final post) when post.id == postId:
          state = AsyncData(post);
          unawaited(_repo.cachePost(post));
        case ReactionSynced(postId: final id, :final result) when id == postId && current != null:
          state = AsyncData(current.withServerReaction(result));
        case PostRemoved(postId: final id) when id == postId:
          state = const AsyncData(null);
        default:
          break;
      }
    });
    final seed = _seed();
    if (seed != null) {
      // A queued post isn't on the server yet — nothing to revalidate.
      if (!seed.pendingSync) unawaited(Future.microtask(_revalidate));
      return seed;
    }
    return _repo.fetchPost(postId);
  }

  Post? _seed() {
    if (ref.exists(feedProvider)) {
      for (final p in ref.read(feedProvider).items) {
        if (p.id == postId) return p;
      }
    }
    for (final p in _repo.pendingPosts()) {
      if (p.id == postId) return p;
    }
    return null;
  }

  Future<void> _revalidate() async {
    try {
      final fresh = await _repo.fetchPost(postId, force: true);
      if (!ref.mounted) return;
      if (fresh == null) {
        state = const AsyncData(null);
      } else {
        ref.read(postEventsProvider.notifier).emit(PostChanged(fresh));
      }
    } on Object {
      // Keep showing the seeded copy; pull-to-refresh can retry.
    }
  }

  Future<void> refresh() async {
    if (state.value?.pendingSync ?? false) return;
    try {
      final fresh = await _repo.fetchPost(postId, force: true);
      if (!ref.mounted) return;
      if (fresh == null) {
        state = const AsyncData(null);
      } else {
        ref.read(postEventsProvider.notifier).emit(PostChanged(fresh));
        state = AsyncData(fresh);
      }
    } on Object catch (e, st) {
      if (!ref.mounted) return;
      if (!state.hasValue) state = AsyncError(e, st);
      rethrow;
    }
  }
}

final postDetailProvider = AsyncNotifierProvider.autoDispose.family<PostDetailNotifier, Post?, String>(
  PostDetailNotifier.new,
);

/// Post-level actions shared by every screen that shows a [Post].
class PostActions {
  PostActions(this._ref);

  final Ref _ref;

  FeedRepository get _repo => _ref.read(feedRepositoryProvider);

  void _emit(PostEvent e) => _ref.read(postEventsProvider.notifier).emit(e);

  /// Deletes the post on the server, then removes it from every list.
  Future<void> delete(Post post) async {
    await _repo.deletePost(post);
    _emit(PostRemoved(post.id));
  }

  Future<void> report(ReportTarget target, String targetId, ReportReason reason) =>
      _repo.report(target: target, targetId: targetId, reason: reason);

  /// Blocks the author and drops their posts from every list.
  Future<void> blockAuthor(String userId) async {
    await _ref.read(friendsRepositoryProvider).block(userId);
    _ref.read(relationshipSeedsProvider).put(userId, Relationship.blocked);
    _emit(AuthorHidden(userId));
  }

  void created(Post post) => _emit(PostCreated(post));

  void changed(Post post) => _emit(PostChanged(post));
}

final postActionsProvider = Provider<PostActions>(PostActions.new);

/// Unread conversations (chat badge on the Community app bar).
final unreadChatsCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(feedRepositoryProvider).unreadConversationsCount(),
);
