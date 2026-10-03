import 'dart:async';

import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/offline/offline_queue.dart';
import 'package:prostuti/features/feed/data/comment.dart';
import 'package:prostuti/features/feed/data/post.dart';

/// Outbox operation types owned by the community features.
abstract final class SocialOps {
  static const createPost = 'feed.createPost';
  static const addComment = 'feed.addComment';
  static const react = 'feed.react';
  static const commentLike = 'feed.commentLike';
  static const respondRequest = 'friends.respond';

  static const all = [createPost, addComment, react, commentLike, respondRequest];
}

/// Whether community writes are still waiting in the outbox. Other features'
/// backlog doesn't matter for ordering, so it doesn't force our writes into
/// the queue while online.
bool hasSocialBacklog() {
  final queue = OfflineQueue.instance;
  if (queue.pendingCount.value == 0) return false;
  try {
    return SocialOps.all.any((type) => queue.pendingOf(type).isNotEmpty);
  } on Object {
    return false;
  }
}

/// Runs [direct] right away when the device is online and no older community
/// write is waiting in the outbox; otherwise — offline, a network failure, or
/// earlier offline writes still queued (FIFO must hold: a comment can't
/// overtake its post) — persists `type`/`payload` to the [OfflineQueue].
///
/// Returns the direct result, or `null` when the write was queued. Business
/// errors (403/404/409 …) are rethrown so the UI can roll back.
Future<T?> runOrQueue<T>(
  String type,
  Map<String, dynamic> payload, {
  required String id,
  required Future<T> Function() direct,
}) async {
  final queue = OfflineQueue.instance;
  final connectivity = ConnectivityService.instance;
  if (connectivity.isOnline && !hasSocialBacklog()) {
    try {
      final result = await direct();
      connectivity.reportSuccess();
      return result;
    } on Object catch (e) {
      if (AppFailure.from(e) is! NetworkFailure) rethrow;
      connectivity.reportFailure();
    }
  }
  await queue.run(type, payload, id: id);
  // Online but queued behind older writes → push the outbox now instead of
  // waiting for the next connectivity change.
  if (connectivity.isOnline) unawaited(queue.flush());
  return null;
}

/// Payloads of [type] still waiting in the outbox (empty when the outbox
/// isn't initialised, e.g. in tests).
List<Map<String, dynamic>> pendingPayloads(String type) {
  try {
    return [for (final op in OfflineQueue.instance.pendingOf(type)) op.payload];
  } on Object {
    return const [];
  }
}

/// A queued write that the outbox has now delivered.
sealed class SocialSync {
  const SocialSync();
}

final class SyncedPost extends SocialSync {
  const SyncedPost(this.post);
  final Post post;
}

final class SyncedComment extends SocialSync {
  const SyncedComment(this.comment);
  final Comment comment;
}

final class SyncedReaction extends SocialSync {
  const SyncedReaction(this.postId, this.result);
  final String postId;
  final ReactionResult result;
}

final class SyncedCommentLike extends SocialSync {
  const SyncedCommentLike({required this.commentId, required this.liked, required this.likeCount});
  final String commentId;
  final bool liked;
  final int likeCount;
}
