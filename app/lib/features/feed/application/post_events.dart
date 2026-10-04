import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/pagination/paged_notifier.dart';
import 'package:prostuti/core/pagination/paged_state.dart';
import 'package:prostuti/features/feed/data/feed_repository.dart';
import 'package:prostuti/features/feed/data/offline_ops.dart';
import 'package:prostuti/features/feed/data/post.dart';

/// Something happened to a post that every list showing it should reflect
/// (the main feed, a profile's posts, the detail screen…).
sealed class PostEvent {
  const PostEvent();
}

/// A post was created by me.
final class PostCreated extends PostEvent {
  const PostCreated(this.post);
  final Post post;
}

/// A post changed (reaction, edit, comment count).
final class PostChanged extends PostEvent {
  const PostChanged(this.post);
  final Post post;
}

/// A post was deleted (or hidden for me).
final class PostRemoved extends PostEvent {
  const PostRemoved(this.postId);
  final String postId;
}

/// I blocked [authorId] — drop all of their posts.
final class AuthorHidden extends PostEvent {
  const AuthorHidden(this.authorId);
  final String authorId;
}

/// I unblocked [authorId] — lists of only their posts refetch them.
final class AuthorUnblocked extends PostEvent {
  const AuthorUnblocked(this.authorId);
  final String authorId;
}

/// A reaction queued offline reached the server; adopt its counts.
final class ReactionSynced extends PostEvent {
  const ReactionSynced(this.postId, this.result);
  final String postId;
  final ReactionResult result;
}

/// A tiny in-app event bus. Each emitted event is a new object, so listeners
/// fire even when two consecutive events carry equal data. Writes replayed
/// by the offline outbox are re-broadcast here too.
class PostEventBus extends Notifier<PostEvent?> {
  @override
  PostEvent? build() {
    final sub = ref.watch(feedRepositoryProvider).synced.listen((sync) {
      switch (sync) {
        case SyncedPost(:final post):
          emit(PostChanged(post));
        case SyncedReaction(:final postId, :final result):
          emit(ReactionSynced(postId, result));
        case SyncedComment() || SyncedCommentLike():
          break;
      }
    });
    ref.onDispose(() => unawaited(sub.cancel()));
    return null;
  }

  // ignore: use_setters_to_change_properties — an event bus "emits", it has no property.
  void emit(PostEvent event) => state = event;
}

final postEventsProvider = NotifierProvider<PostEventBus, PostEvent?>(PostEventBus.new);

/// Keeps a paged list of posts in sync with [postEventsProvider].
mixin PostListSync on PagedNotifier<Post, Keyset> {
  /// Call from `build()` before `super.build()`.
  void listenToPostEvents() {
    ref.listen<PostEvent?>(postEventsProvider, (_, event) {
      if (event != null) applyPostEvent(event);
    });
  }

  /// Whether a newly created post belongs in this list.
  bool acceptsNewPost(Post post) => true;

  void applyPostEvent(PostEvent event) {
    switch (event) {
      case PostCreated(:final post):
        if (acceptsNewPost(post)) upsertFirst(post);
      case PostChanged(:final post):
        if (_contains(post.id)) replace(post);
      case PostRemoved(:final postId):
        if (_contains(postId)) removeWhere((p) => p.id == postId);
      case AuthorHidden(:final authorId):
        if (state.items.any((p) => p.author.id == authorId)) removeWhere((p) => p.author.id == authorId);
      case AuthorUnblocked():
        break; // Their posts come back with the next fetch.
      case ReactionSynced(:final postId, :final result):
        final current = _find(postId);
        if (current != null) replace(current.withServerReaction(result));
    }
  }

  bool _contains(String id) => _find(id) != null;

  Post? _find(String id) {
    for (final p in state.items) {
      if (p.id == id) return p;
    }
    return null;
  }
}

/// Merges posts still waiting in the outbox (newest first) on top of a
/// fetched/cached page and re-applies queued reactions (the last one per
/// post wins), so offline work survives an app restart. Pure.
List<Post> mergePendingWrites(
  List<Post> page, {
  List<Post> pendingPosts = const [],
  List<(String, ReactionType?)> reactions = const [],
}) {
  final ids = {for (final p in page) p.id};
  var items = [...pendingPosts.where((p) => !ids.contains(p.id)), ...page];
  if (reactions.isNotEmpty) {
    final last = <String, ReactionType?>{for (final (id, type) in reactions) id: type};
    items = [
      for (final p in items)
        if (last.containsKey(p.id)) p.withReaction(last[p.id]) else p,
    ];
  }
  return items;
}

/// `nextCursor` helper for keyset pages: a short page means the end.
PageResult<T, Keyset> keysetPage<T>(List<T> items, int pageSize, Keyset Function(T item) cursorOf) =>
    PageResult(items, items.length < pageSize || items.isEmpty ? null : cursorOf(items.last));
