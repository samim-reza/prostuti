import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/features/feed/application/post_events.dart';
import 'package:prostuti/features/feed/application/reaction_controller.dart';
import 'package:prostuti/features/feed/data/post.dart';
import 'package:prostuti/features/profile/data/profile.dart';

Post _post({Map<ReactionType, int> summary = const {}, int? count, ReactionType? mine, String id = 'p1'}) => Post(
  id: id,
  author: const UserSummary(id: 'a', username: 'author'),
  createdAt: DateTime.utc(2026, 10, 4),
  reactionSummary: summary,
  reactionCount: count ?? summary.values.fold(0, (a, b) => a + b),
  myReaction: mine,
);

void main() {
  group('Post.withReaction (optimistic reducer)', () {
    test('adding a reaction increments its bucket and the total', () {
      final p = _post(summary: {ReactionType.love: 2}).withReaction(ReactionType.like);
      expect(p.myReaction, ReactionType.like);
      expect(p.reactionSummary, {ReactionType.love: 2, ReactionType.like: 1});
      expect(p.reactionCount, 3);
    });

    test('switching moves my vote between buckets; total unchanged', () {
      final p = _post(
        summary: {ReactionType.like: 1, ReactionType.love: 2},
        mine: ReactionType.like,
      ).withReaction(ReactionType.love);
      expect(p.myReaction, ReactionType.love);
      expect(p.reactionSummary, {ReactionType.love: 3});
      expect(p.reactionCount, 3);
    });

    test('removing drops an emptied bucket and decrements the total', () {
      final p = _post(summary: {ReactionType.haha: 1}, mine: ReactionType.haha).withReaction(null);
      expect(p.myReaction, isNull);
      expect(p.reactionSummary, isEmpty);
      expect(p.reactionCount, 0);
    });

    test('same reaction is a no-op', () {
      final p = _post(summary: {ReactionType.wow: 1}, mine: ReactionType.wow);
      expect(identical(p.withReaction(ReactionType.wow), p), isTrue);
    });

    test('never goes negative with inconsistent data', () {
      final p = _post(count: 0, mine: ReactionType.sad).withReaction(null);
      expect(p.reactionCount, 0);
      expect(p.reactionSummary, isEmpty);
    });

    test('withServerReaction adopts authoritative counts', () {
      final p = _post(summary: {ReactionType.like: 1}, mine: ReactionType.like).withServerReaction(
        const ReactionResult(reactionCount: 7, summary: {ReactionType.like: 4, ReactionType.angry: 3}),
      );
      expect(p.myReaction, isNull);
      expect(p.reactionCount, 7);
      expect(p.reactionSummary[ReactionType.angry], 3);
    });
  });

  group('ReactionController', () {
    late List<Post> published;
    late List<(String, ReactionType?)> sent;
    late List<Completer<ReactionResult?>> pending;
    late ReactionController controller;

    setUp(() {
      published = [];
      sent = [];
      pending = [];
      controller = ReactionController(
        send: (id, type) {
          sent.add((id, type));
          final c = Completer<ReactionResult?>();
          pending.add(c);
          return c.future;
        },
        publish: published.add,
        interval: Duration.zero,
      );
    });

    tearDown(() => controller.dispose());

    test('publishes optimistically, then the server summary', () async {
      final post = _post(summary: {ReactionType.love: 1});
      controller.toggle(post);
      expect(published.single.myReaction, ReactionType.like);
      expect(published.single.reactionCount, 2);
      expect(sent.single, ('p1', ReactionType.like));

      pending.single.complete(
        const ReactionResult(
          reactionCount: 5,
          summary: {ReactionType.like: 3, ReactionType.love: 2},
          myReaction: ReactionType.like,
        ),
      );
      await pumpEventQueue();
      expect(published.last.reactionCount, 5);
      expect(controller.isPending('p1'), isFalse);
    });

    test('rolls back to the confirmed state on failure', () async {
      Object? error;
      final post = _post(summary: {ReactionType.wow: 2}, mine: ReactionType.wow);
      controller.toggle(post, onError: (e) => error = e);
      expect(published.single.myReaction, isNull);
      expect(published.single.reactionCount, 1);

      pending.single.completeError(Exception('boom'));
      await pumpEventQueue();
      expect(error, isNotNull);
      expect(published.last.myReaction, ReactionType.wow);
      expect(published.last.reactionCount, 2);
      expect(published.last.reactionSummary, {ReactionType.wow: 2});
    });

    test('serializes per post: a change made in flight is sent after the reply', () async {
      final post = _post();
      controller.set(post, ReactionType.like);
      final liked = published.last;
      controller.set(liked, ReactionType.angry);
      await pumpEventQueue();
      // Only one request may be in flight for the post.
      expect(sent, [('p1', ReactionType.like)]);

      pending.first.complete(
        const ReactionResult(reactionCount: 1, summary: {ReactionType.like: 1}, myReaction: ReactionType.like),
      );
      await pumpEventQueue();
      expect(sent, [('p1', ReactionType.like), ('p1', ReactionType.angry)]);
      // The stale "like" answer must not overwrite the newer choice in the UI.
      expect(published.last.myReaction, ReactionType.angry);

      pending.last.complete(
        const ReactionResult(reactionCount: 1, summary: {ReactionType.angry: 1}, myReaction: ReactionType.angry),
      );
      await pumpEventQueue();
      expect(published.last.myReaction, ReactionType.angry);
      expect(published.last.reactionSummary, {ReactionType.angry: 1});
      expect(controller.isPending('p1'), isFalse);
    });

    test('a queued (offline) write keeps the optimistic state', () async {
      final post = _post(summary: {ReactionType.like: 1});
      controller.set(post, ReactionType.love);
      pending.single.complete(null);
      await pumpEventQueue();
      expect(published, hasLength(1));
      expect(published.single.myReaction, ReactionType.love);
      expect(controller.isPending('p1'), isFalse);
    });

    test('throttles rapid taps to the final choice', () async {
      final throttled = ReactionController(
        send: (id, type) {
          sent.add((id, type));
          return Future.value(ReactionResult(reactionCount: type == null ? 0 : 1, summary: const {}, myReaction: type));
        },
        publish: published.add,
        interval: const Duration(milliseconds: 50),
      );
      addTearDown(throttled.dispose);
      var post = _post();
      for (var i = 0; i < 5; i++) {
        throttled.toggle(post);
        post = published.last;
      }
      // like, none, like, none, like → final state "like".
      expect(post.myReaction, ReactionType.like);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(sent.first, ('p1', ReactionType.like));
      expect(sent.length, lessThan(5));
      expect(sent.last.$2, ReactionType.like);
    });
  });

  group('mergePendingWrites', () {
    final server = [
      _post(id: 'a'),
      _post(id: 'b', summary: {ReactionType.like: 1}),
    ];

    test('puts queued posts on top and skips ones already on the server', () {
      final queued = _post(id: 'q');
      final merged = mergePendingWrites(
        server,
        pendingPosts: [
          queued,
          _post(id: 'a'),
        ],
      );
      expect(merged.map((p) => p.id), ['q', 'a', 'b']);
    });

    test('re-applies the last queued reaction per post', () {
      final merged = mergePendingWrites(
        server,
        reactions: [('b', ReactionType.love), ('b', null), ('a', ReactionType.haha)],
      );
      expect(merged[0].myReaction, ReactionType.haha);
      expect(merged[0].reactionCount, 1);
      expect(merged[1].myReaction, isNull);
      expect(merged[1].reactionCount, 1, reason: 'already in sync → unchanged');
    });
  });
}
