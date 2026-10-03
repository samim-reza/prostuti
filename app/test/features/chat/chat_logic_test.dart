import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/features/chat/application/chat_logic.dart';
import 'package:prostuti/features/chat/application/chat_room.dart';
import 'package:prostuti/features/chat/data/chat_models.dart';
import 'package:prostuti/features/profile/data/profile.dart';

const me = 'me';
const other = 'other';
const conv = 'c1';

final t0 = DateTime.utc(2026, 10, 4, 6); // 12:00 in Dhaka

ChatMessage msg(
  String id, {
  String sender = other,
  Duration at = Duration.zero,
  MessageStatus status = MessageStatus.sent,
  MessageKind kind = MessageKind.text,
  DateTime? deletedAt,
}) => ChatMessage(
  id: id,
  conversationId: conv,
  senderId: sender,
  createdAt: t0.add(at),
  body: 'body $id',
  kind: kind,
  status: status,
  deletedAt: deletedAt,
);

List<String> ids(List<ChatMessage> l) => [for (final m in l) m.id];

void main() {
  group('mergeMessage (optimistic merge / de-dup)', () {
    test('server confirmation replaces the optimistic bubble (same client id)', () {
      final optimistic = msg('a', sender: me, at: const Duration(minutes: 1), status: MessageStatus.sending);
      var list = mergeMessage([msg('x')], optimistic);
      expect(ids(list), ['a', 'x']);

      final confirmed = msg('a', sender: me, at: const Duration(minutes: 1, seconds: 2));
      list = mergeMessage(list, confirmed);
      expect(ids(list), ['a', 'x']);
      expect(list.first.status, MessageStatus.sent);
      expect(list.first.createdAt, confirmed.createdAt);
    });

    test('Realtime echo + insert response never duplicate', () {
      final optimistic = msg('a', sender: me, at: const Duration(minutes: 1), status: MessageStatus.sending);
      final server = msg('a', sender: me, at: const Duration(minutes: 1));
      var list = mergeMessage(const [], optimistic);
      list = mergeMessage(list, server); // Realtime INSERT arrives first
      list = mergeMessage(list, server); // then the HTTP response
      expect(ids(list), ['a']);
    });

    test('a late optimistic state does not downgrade a confirmed message', () {
      final server = msg('a', sender: me);
      final list = mergeMessage([server], server.copyWith(status: MessageStatus.failed));
      expect(list.single.status, MessageStatus.sent);
    });

    test('pending messages stay newest until confirmed; confirmed ones sort by time', () {
      final pending = msg('p', sender: me, at: const Duration(minutes: 10), status: MessageStatus.sending);
      var list = mergeMessage([msg('old')], pending);
      // A message from someone else arrives while ours is still sending.
      list = mergeMessage(list, msg('incoming', at: const Duration(minutes: 11)));
      expect(ids(list), ['p', 'incoming', 'old']);
      // Our message is confirmed with a server time *before* the incoming one.
      list = mergeMessage(list, msg('p', sender: me, at: const Duration(minutes: 10, seconds: 30)));
      expect(ids(list), ['incoming', 'p', 'old']);
    });

    test('out-of-order rows are placed by created_at (ties by id)', () {
      var list = <ChatMessage>[];
      for (final m in [
        msg('b', at: const Duration(minutes: 2)),
        msg('a', at: const Duration(minutes: 1)),
        msg('d', at: const Duration(minutes: 4)),
        msg('c', at: const Duration(minutes: 2)),
      ]) {
        list = mergeMessage(list, m);
      }
      expect(ids(list), ['d', 'c', 'b', 'a']);
    });

    test('updates (soft delete) replace in place', () {
      final list = [msg('b', at: const Duration(minutes: 2)), msg('a', at: const Duration(minutes: 1))];
      final deleted = mergeMessage(list, msg('a', at: const Duration(minutes: 1), deletedAt: t0));
      expect(ids(deleted), ['b', 'a']);
      expect(deleted.last.isDeleted, isTrue);
    });

    test('local image bytes survive the swap to the server row', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final optimistic = msg(
        'img',
        sender: me,
        kind: MessageKind.image,
        status: MessageStatus.sending,
      ).copyWith(localBytes: bytes);
      final list = mergeMessage(mergeMessage(const [], optimistic), msg('img', sender: me, kind: MessageKind.image));
      expect(list.single.localBytes, same(bytes));
      expect(list.single.isPending, isFalse);
    });

    test('newestConfirmed skips pending messages', () {
      final list = [msg('p', sender: me, status: MessageStatus.sending), msg('b', at: const Duration(minutes: 2))];
      expect(newestConfirmed(list)?.id, 'b');
      expect(newestConfirmed(const []), isNull);
    });
  });

  group('buildTimeline (grouping + day separators)', () {
    test('groups consecutive messages of one sender within 5 minutes', () {
      // newest first
      final list = [
        msg('m4', sender: me, at: const Duration(minutes: 20)),
        msg('m3', at: const Duration(minutes: 12)), // > 5 min after m2 → new group
        msg('m2', at: const Duration(minutes: 3)),
        msg('m1'),
      ];
      final entries = buildTimeline(list);
      final messages = entries.whereType<MessageEntry>().toList();
      expect([for (final e in messages) e.message.id], ['m4', 'm3', 'm2', 'm1']);

      MessageEntry e(String id) => messages.firstWhere((x) => x.message.id == id);
      expect((e('m1').isFirstInGroup, e('m1').isLastInGroup), (true, false));
      expect((e('m2').isFirstInGroup, e('m2').isLastInGroup), (false, true));
      expect((e('m3').isFirstInGroup, e('m3').isLastInGroup), (true, true));
      expect((e('m4').isFirstInGroup, e('m4').isLastInGroup), (true, true));
    });

    test('system messages never join a group', () {
      final list = [
        msg('b', at: const Duration(minutes: 1)),
        msg('sys', kind: MessageKind.system, at: const Duration(seconds: 30)),
        msg('a'),
      ];
      final m = buildTimeline(list).whereType<MessageEntry>().toList();
      expect(m.every((e) => e.isFirstInGroup && e.isLastInGroup), isTrue);
    });

    test("one separator per Bangladesh day, above that day's oldest message", () {
      // 17:30Z = 23:30 Dhaka (day 1); 18:30Z = 00:30 Dhaka (day 2).
      final day1Late = DateTime.utc(2026, 10, 3, 17, 30);
      final day2Early = DateTime.utc(2026, 10, 3, 18, 30);
      ChatMessage at(String id, DateTime t) => ChatMessage(id: id, conversationId: conv, senderId: other, createdAt: t);
      final list = [
        at('d2b', day2Early.add(const Duration(minutes: 2))),
        at('d2a', day2Early),
        at('d1b', day1Late),
        at('d1a', day1Late.subtract(const Duration(hours: 3))),
      ];
      final entries = buildTimeline(list);
      final shape = [
        for (final e in entries)
          switch (e) {
            MessageEntry(:final message) => message.id,
            DayEntry(:final day) => 'day:${day.day}',
          },
      ];
      expect(shape, ['d2b', 'd2a', 'day:4', 'd1b', 'd1a', 'day:3']);

      // A day change also breaks a sender group even within 5 minutes.
      final m = entries.whereType<MessageEntry>().toList();
      expect(m.firstWhere((e) => e.message.id == 'd2a').isFirstInGroup, isTrue);
    });

    test('empty list → empty timeline', () {
      expect(buildTimeline(const []), isEmpty);
    });

    test('day label kinds', () {
      final today = DateTime.utc(2026, 10, 4);
      expect(dayLabelKind(today, today), DayLabelKind.today);
      expect(dayLabelKind(DateTime.utc(2026, 10, 3), today), DayLabelKind.yesterday);
      expect(dayLabelKind(DateTime.utc(2026, 9, 30), today), DayLabelKind.date);
    });

    test('bdDay converts instants to the Dhaka calendar day', () {
      expect(bdDay(DateTime.utc(2026, 10, 3, 18)), DateTime.utc(2026, 10, 4));
      expect(bdDay(DateTime.utc(2026, 10, 3, 17, 59)), DateTime.utc(2026, 10, 3));
    });
  });

  group('computeSeen (read receipts)', () {
    final mine = msg('m', sender: me, at: const Duration(minutes: 5));

    test('direct chat: seen once the other member read past my message', () {
      final list = [mine, msg('x')];
      expect(computeSeen(list, me, {other: t0})!.isSeen, isFalse);
      final seen = computeSeen(list, me, {other: t0.add(const Duration(minutes: 5))})!;
      expect(seen.messageId, 'm');
      expect(seen.isSeen, isTrue);
    });

    test('group: counts members who read it', () {
      final s = computeSeen([mine], me, {'a': t0.add(const Duration(minutes: 6)), 'b': t0, 'c': null})!;
      expect((s.seenBy, s.others), (1, 3));
    });

    test('ignores pending messages and hides receipts after a reply', () {
      final pending = msg('p', sender: me, at: const Duration(minutes: 9), status: MessageStatus.sending);
      expect(computeSeen([pending, mine], me, {other: t0.add(const Duration(hours: 1))})?.messageId, 'm');
      expect(computeSeen([msg('reply', at: const Duration(minutes: 8)), mine], me, {other: t0}), isNull);
      expect(computeSeen(const [], me, {other: t0}), isNull);
    });
  });

  group('applyConversationUpdate (inbox patching)', () {
    ConversationSummary c(String id, Duration at, {int unread = 0}) => ConversationSummary(
      id: id,
      kind: ConversationKind.direct,
      otherUser: UserSummary(id: 'u-$id', username: 'u$id'),
      lastMessageAt: t0.add(at),
      lastMessagePreview: 'old',
      unreadCount: unread,
    );

    final items = [c('a', const Duration(minutes: 3)), c('b', const Duration(minutes: 2), unread: 1)];

    Map<String, dynamic> row(String id, Duration at, String sender) => {
      'id': id,
      'last_message_at': t0.add(at).toIso8601String(),
      'last_message_preview': 'new',
      'last_message_sender': sender,
    };

    test('new incoming message: patch, move to top, unread + 1', () {
      final next = applyConversationUpdate(items, row('b', const Duration(minutes: 5), other), myId: me)!;
      expect(ids2(next), ['b', 'a']);
      expect(next.first.unreadCount, 2);
      expect(next.first.lastMessagePreview, 'new');
    });

    test('my own message resets unread', () {
      final next = applyConversationUpdate(items, row('b', const Duration(minutes: 5), me), myId: me)!;
      expect(next.first.unreadCount, 0);
      expect(next.first.lastMessageSender, me);
    });

    test('the open conversation stays at 0 unread', () {
      final next = applyConversationUpdate(
        items,
        row('b', const Duration(minutes: 5), other),
        myId: me,
        activeConversationId: 'b',
      )!;
      expect(next.first.unreadCount, 0);
    });

    test('non-message updates (rename) keep position and unread', () {
      final next = applyConversationUpdate(items, {
        'id': 'b',
        'title': 'Renamed',
        'last_message_at': t0.add(const Duration(minutes: 2)).toIso8601String(),
      }, myId: me)!;
      expect(ids2(next), ['a', 'b']);
      expect(next.last.unreadCount, 1);
      expect(next.last.title, 'Renamed');
    });

    test('unknown conversation → null (caller refreshes)', () {
      expect(applyConversationUpdate(items, row('zzz', const Duration(minutes: 9), other), myId: me), isNull);
    });

    test('filterConversations matches name, username and preview', () {
      String name(ConversationSummary x) => x.id == 'a' ? 'রহিম উদ্দিন' : 'Karim';
      expect(ids2(filterConversations(items, 'রহিম', nameOf: name)), ['a']);
      expect(ids2(filterConversations(items, 'KAR', nameOf: name)), ['b']);
      expect(ids2(filterConversations(items, 'ub', nameOf: name)), ['b']); // username "ub"
      expect(filterConversations(items, '  ', nameOf: name), same(items));
    });
  });

  group('inboxTime', () {
    final now = DateTime.utc(2026, 10, 4, 10); // 16:00 Dhaka
    test('buckets', () {
      expect(inboxTime(now.subtract(const Duration(seconds: 20)), now).$1, InboxTimeUnit.justNow);
      expect(inboxTime(now.subtract(const Duration(minutes: 7)), now), (InboxTimeUnit.minutes, 7));
      expect(inboxTime(now.subtract(const Duration(hours: 3)), now), (InboxTimeUnit.hours, 3));
      expect(inboxTime(now.subtract(const Duration(hours: 20)), now).$1, InboxTimeUnit.yesterday);
      expect(inboxTime(now.subtract(const Duration(days: 3)), now), (InboxTimeUnit.days, 3));
      expect(inboxTime(now.subtract(const Duration(days: 10)), now).$1, InboxTimeUnit.date);
    });
  });

  group('TypingThrottle', () {
    test('sends at most once per 2 seconds; reset allows an immediate send', () {
      final t = TypingThrottle();
      final start = DateTime(2026);
      expect(t.shouldSend(start), isTrue);
      expect(t.shouldSend(start.add(const Duration(milliseconds: 500))), isFalse);
      expect(t.shouldSend(start.add(const Duration(milliseconds: 1999))), isFalse);
      expect(t.shouldSend(start.add(const Duration(seconds: 2))), isTrue);
      t.reset();
      expect(t.shouldSend(start.add(const Duration(seconds: 2, milliseconds: 100))), isTrue);
    });
  });
}

List<String> ids2(List<ConversationSummary> l) => [for (final c in l) c.id];
