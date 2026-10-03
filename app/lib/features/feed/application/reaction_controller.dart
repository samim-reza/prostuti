import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/rate_limit/debouncer.dart';
import 'package:prostuti/features/feed/application/post_events.dart';
import 'package:prostuti/features/feed/data/feed_repository.dart';
import 'package:prostuti/features/feed/data/post.dart';

/// Sends a reaction; returns the server's summary, or `null` when the write
/// was queued in the offline outbox (the optimistic state then stands and
/// the outbox's replay later broadcasts the real counts).
typedef ReactionSender = Future<ReactionResult?> Function(String postId, ReactionType? type);

/// Optimistic, throttled and per-post serialized reactions.
///
/// * The UI changes instantly ([Post.withReaction]) and the change is
///   broadcast to every list showing the post.
/// * Rapid taps are throttled; the trailing call sends the *final* choice.
/// * At most one request per post is in flight, so the server can never
///   apply two requests out of order. A choice made while a request is in
///   flight is sent as soon as it returns.
/// * The server's summary replaces the local counts once the UI and server
///   agree; on failure the reaction rolls back to the last confirmed state.
/// * Offline, the write is queued and the optimistic state is kept.
class ReactionController {
  ReactionController({required this.send, required this.publish, this.interval = const Duration(milliseconds: 600)});

  final ReactionSender send;
  final void Function(Post post) publish;
  final Duration interval;

  final _throttlers = <String, Throttler>{};

  /// State before the first unconfirmed change (rollback target).
  final _confirmed = <String, Post>{};

  /// Latest local (optimistic) state of posts with unsent/unconfirmed changes.
  final _latest = <String, Post>{};
  final _inFlight = <String>{};
  final _dirty = <String>{};
  bool _disposed = false;

  /// Tap on the react button: like, or remove whatever reaction I gave.
  void toggle(Post post, {void Function(Object error)? onError}) =>
      set(post, post.myReaction == null ? ReactionType.like : null, onError: onError);

  /// Sets my reaction to [next] (`null` removes it).
  void set(Post post, ReactionType? next, {void Function(Object error)? onError}) {
    if (_disposed || post.myReaction == next) return;
    _confirmed.putIfAbsent(post.id, () => post);
    final optimistic = post.withReaction(next);
    _latest[post.id] = optimistic;
    publish(optimistic);
    _throttlers.putIfAbsent(post.id, () => Throttler(interval)).call(() => unawaited(_flush(post.id, onError)));
  }

  /// Whether [postId] has a change that the server hasn't confirmed yet.
  bool isPending(String postId) => _latest.containsKey(postId);

  Future<void> _flush(String postId, void Function(Object error)? onError) async {
    if (_disposed) return;
    if (_inFlight.contains(postId)) {
      _dirty.add(postId);
      return;
    }
    final desired = _latest[postId];
    if (desired == null) return;
    final sent = desired.myReaction;
    _inFlight.add(postId);
    try {
      final result = await send(postId, sent);
      if (_disposed) return;
      final latest = _latest[postId] ?? desired;
      if (result == null) {
        // Queued offline: the outbox owns it now (and keeps FIFO order for
        // any later change), so there is nothing to confirm or roll back.
        if (latest.myReaction == sent) {
          _latest.remove(postId);
          _confirmed.remove(postId);
        } else {
          _confirmed[postId] = desired;
          _dirty.add(postId);
        }
      } else if (latest.myReaction == result.myReaction) {
        // UI and server agree → adopt the authoritative counts.
        _latest.remove(postId);
        _confirmed.remove(postId);
        publish(latest.withServerReaction(result));
      } else {
        // The user changed their mind meanwhile; remember the server state
        // as the new rollback target and send the latest choice next.
        _confirmed[postId] = latest.withServerReaction(result);
        _dirty.add(postId);
      }
    } on Object catch (e) {
      if (_disposed) return;
      final rollback = _confirmed.remove(postId);
      final latest = _latest.remove(postId);
      _dirty.remove(postId);
      if (rollback != null) {
        publish(
          (latest ?? rollback).copyWith(
            reactionCount: rollback.reactionCount,
            reactionSummary: rollback.reactionSummary,
            myReaction: rollback.myReaction,
            clearMyReaction: rollback.myReaction == null,
          ),
        );
      }
      onError?.call(e);
    } finally {
      _inFlight.remove(postId);
    }
    if (_dirty.remove(postId) && _latest.containsKey(postId)) {
      await _flush(postId, onError);
    }
  }

  void dispose() {
    _disposed = true;
    for (final t in _throttlers.values) {
      t.dispose();
    }
    _throttlers.clear();
  }
}

final reactionControllerProvider = Provider<ReactionController>((ref) {
  final repo = ref.watch(feedRepositoryProvider);
  final controller = ReactionController(
    send: repo.reactOrQueue,
    publish: (post) => ref.read(postEventsProvider.notifier).emit(PostChanged(post)),
  );
  ref.onDispose(controller.dispose);
  return controller;
});
