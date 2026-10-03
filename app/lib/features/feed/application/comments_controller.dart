import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/pagination/paged_notifier.dart';
import 'package:prostuti/core/pagination/paged_state.dart';
import 'package:prostuti/features/feed/application/feed_controller.dart';
import 'package:prostuti/features/feed/application/post_events.dart';
import 'package:prostuti/features/feed/data/comment.dart';
import 'package:prostuti/features/feed/data/feed_repository.dart';
import 'package:prostuti/features/feed/data/offline_ops.dart';
import 'package:prostuti/features/feed/data/post.dart';
import 'package:prostuti/features/feed/data/report.dart';
import 'package:prostuti/features/profile/data/profile.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';

/// Shared logic for comment lists (oldest first, keyset on `(created_at, id)`).
///
/// The first top-level page is persisted (instant + offline paint), queued
/// offline comments are appended with a pending-sync marker, and outbox
/// replays swap them for the server copy.
abstract class _CommentListNotifier extends PagedNotifier<Comment, Keyset> {
  /// Comments I just wrote while older pages were still unloaded. They stay
  /// pinned at the end of the list until every page has been merged.
  final _local = <String>{};

  String get postId;
  String? get parentId;

  FeedRepository get _repo => ref.read(feedRepositoryProvider);

  @override
  PagedState<Comment, Keyset> build() {
    final sub = ref.watch(feedRepositoryProvider).synced.listen((sync) {
      switch (sync) {
        case SyncedComment(:final comment) when comment.postId == postId && comment.parentId == parentId:
          if (find(comment.id) != null) replace(comment);
        case SyncedCommentLike(:final commentId, :final liked, :final likeCount):
          final current = find(commentId);
          if (current != null) replace(current.copyWith(likedByMe: liked, likeCount: likeCount));
        default:
          break;
      }
    });
    ref.onDispose(() => unawaited(sub.cancel()));
    return super.build();
  }

  List<Comment> _withPending(List<Comment> page) {
    final pending = _repo.pendingComments(postId, parentId: parentId);
    if (pending.isEmpty) return page;
    final ids = {for (final c in page) c.id};
    final extra = pending.where((c) => !ids.contains(c.id)).toList();
    _local.addAll(extra.map((c) => c.id));
    return [...page, ...extra];
  }

  @override
  Future<PageResult<Comment, Keyset>> fetchPage(Keyset? cursor) async {
    final items = await _repo.fetchComments(postId, parentId: parentId, after: cursor);
    final page = keysetPage(items, FeedRepository.commentPageSize, (c) => c.cursor);
    return cursor == null ? PageResult(_withPending(items), page.nextCursor) : page;
  }

  @override
  List<Comment>? readCachedFirstPage() {
    if (parentId != null) return null;
    final merged = _withPending(_repo.readCachedComments(postId) ?? const []);
    return merged.isEmpty ? null : merged;
  }

  @override
  Object idOf(Comment item) => item.id;

  @override
  Future<void> loadMore() async {
    await super.loadMore();
    if (_local.isEmpty || !ref.mounted) return;
    final items = state.items;
    state = state.copyWith(
      items: [...items.where((c) => !_local.contains(c.id)), ...items.where((c) => _local.contains(c.id))],
    );
    if (!state.hasMore) _local.clear();
  }

  void append(Comment comment) {
    if (state.items.any((c) => c.id == comment.id)) return;
    if (state.hasMore || comment.pendingSync) _local.add(comment.id);
    state = state.copyWith(items: [...state.items, comment]);
    _persist();
  }

  /// Keeps the offline snapshot of the first page current.
  void _persist() {
    if (parentId == null) unawaited(_repo.cacheComments(postId, state.items));
  }

  Comment? find(String id) {
    for (final c in state.items) {
      if (c.id == id) return c;
    }
    return null;
  }

  void remove(String id) {
    _local.remove(id);
    removeWhere((c) => c.id == id);
    _persist();
  }
}

/// Top-level comments of a post.
class CommentsNotifier extends _CommentListNotifier {
  CommentsNotifier(this.postId);

  @override
  final String postId;

  @override
  String? get parentId => null;
}

final commentsProvider = NotifierProvider.autoDispose.family<CommentsNotifier, PagedState<Comment, Keyset>, String>(
  CommentsNotifier.new,
);

typedef RepliesKey = ({String postId, String parentId});

/// Replies of one top-level comment (loaded only when expanded).
class RepliesNotifier extends _CommentListNotifier {
  RepliesNotifier(this.key);

  final RepliesKey key;

  @override
  String get postId => key.postId;

  @override
  String get parentId => key.parentId;
}

final repliesProvider = NotifierProvider.autoDispose.family<RepliesNotifier, PagedState<Comment, Keyset>, RepliesKey>(
  RepliesNotifier.new,
);

/// Comment actions for one post: keeps the comment lists, reply counts and
/// the post's comment counter (in every feed) consistent.
class CommentActions {
  CommentActions(this._ref, this.postId);

  final Ref _ref;
  final String postId;
  final _liking = <String>{};

  FeedRepository get _repo => _ref.read(feedRepositoryProvider);

  void _bumpPostComments(int delta) {
    final post = _ref.read(postDetailProvider(postId)).value;
    if (post == null) return;
    final next = post.commentCount + delta;
    _ref.read(postEventsProvider.notifier).emit(PostChanged(post.copyWith(commentCount: next < 0 ? 0 : next)));
  }

  /// Posts a comment, or a reply when [replyTo] is given (replies to a reply
  /// attach to its top-level comment, mirroring the database trigger).
  Future<Comment> add(String body, {Comment? replyTo}) async {
    final me = await _me();
    final parentId = replyTo == null ? null : (replyTo.parentId ?? replyTo.id);
    final comment = await _repo.addComment(postId: postId, body: body, author: me, parentId: parentId);
    if (comment.parentId == null) {
      if (_ref.exists(commentsProvider(postId))) _ref.read(commentsProvider(postId).notifier).append(comment);
    } else {
      final key = (postId: postId, parentId: comment.parentId!);
      if (_ref.exists(repliesProvider(key))) _ref.read(repliesProvider(key).notifier).append(comment);
      _updateTopLevel(comment.parentId!, (c) => c.copyWith(replyCount: c.replyCount + 1));
    }
    _bumpPostComments(1);
    return comment;
  }

  Future<void> delete(Comment comment) async {
    await _repo.deleteComment(comment.id);
    if (comment.parentId == null) {
      if (_ref.exists(commentsProvider(postId))) _ref.read(commentsProvider(postId).notifier).remove(comment.id);
      _bumpPostComments(-(1 + comment.replyCount));
    } else {
      final key = (postId: postId, parentId: comment.parentId!);
      if (_ref.exists(repliesProvider(key))) _ref.read(repliesProvider(key).notifier).remove(comment.id);
      _updateTopLevel(comment.parentId!, (c) => c.copyWith(replyCount: c.replyCount > 0 ? c.replyCount - 1 : 0));
      _bumpPostComments(-1);
    }
  }

  /// Optimistic like toggle. Requests carry the *desired* state (the RPC is
  /// a toggle, so the repository converges to it), taps on the same comment
  /// are serialized, and offline the change is queued.
  Future<void> toggleLike(Comment comment) async {
    if (!_liking.add(comment.id)) return;
    final optimistic = comment.toggledLike();
    _replace(optimistic);
    try {
      final result = await _repo.setCommentLikeOrQueue(comment.id, liked: optimistic.likedByMe);
      if (result != null) _replace(optimistic.copyWith(likedByMe: result.$1, likeCount: result.$2));
    } on Object {
      _replace(comment);
      rethrow;
    } finally {
      _liking.remove(comment.id);
    }
  }

  Future<void> report(Comment comment, ReportReason reason) =>
      _repo.report(target: ReportTarget.comment, targetId: comment.id, reason: reason);

  void _replace(Comment c) {
    if (c.parentId == null) {
      if (_ref.exists(commentsProvider(postId))) _ref.read(commentsProvider(postId).notifier).replace(c);
    } else {
      final key = (postId: postId, parentId: c.parentId!);
      if (_ref.exists(repliesProvider(key))) _ref.read(repliesProvider(key).notifier).replace(c);
    }
  }

  void _updateTopLevel(String id, Comment Function(Comment c) update) {
    if (!_ref.exists(commentsProvider(postId))) return;
    final notifier = _ref.read(commentsProvider(postId).notifier);
    final current = notifier.find(id);
    if (current != null) notifier.replace(update(current));
  }

  Future<UserSummary> _me() async {
    final profile = _ref.read(currentProfileProvider).value ?? await _ref.read(currentProfileProvider.future);
    if (profile == null) throw const AuthFailure('not_authenticated');
    return UserSummary(
      id: profile.id,
      username: profile.username,
      fullName: profile.fullName,
      avatarUrl: profile.avatarUrl,
    );
  }
}

final commentActionsProvider = Provider.autoDispose.family<CommentActions, String>(CommentActions.new);
