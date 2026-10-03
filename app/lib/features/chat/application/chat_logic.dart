import 'package:flutter/foundation.dart';
import 'package:prostuti/core/utils/bd_time.dart';
import 'package:prostuti/features/chat/data/chat_models.dart';

// Pure, framework-free chat algorithms (unit tested in
// test/features/chat/chat_logic_test.dart).

// -----------------------------------------------------------------------------
// Optimistic merge / de-duplication
// -----------------------------------------------------------------------------

/// True when [a] should be shown *below* (is newer than) [b].
bool _isNewer(ChatMessage a, ChatMessage b) {
  final c = a.createdAt.compareTo(b.createdAt);
  return c != 0 ? c > 0 : a.id.compareTo(b.id) > 0;
}

/// Inserts or replaces [incoming] in a newest-first list.
///
/// * The client generates message ids, so the optimistic copy, the insert
///   response and the Realtime echo all share one id → never duplicated.
/// * Pending (sending/failed) messages stay at the newest end until the
///   server confirms them; confirmed messages are ordered by server time.
/// * Locally picked image bytes survive the swap to the server row, so an
///   image bubble never flashes while its signed URL loads.
/// * An echo never downgrades a confirmed message back to pending.
List<ChatMessage> mergeMessage(List<ChatMessage> newestFirst, ChatMessage incoming) {
  var message = incoming;
  final existingIndex = newestFirst.indexWhere((m) => m.id == incoming.id);
  final rest = [...newestFirst];
  if (existingIndex >= 0) {
    final existing = rest.removeAt(existingIndex);
    if (incoming.isPending && !existing.isPending) {
      // Late optimistic state after the server already confirmed — ignore.
      return newestFirst;
    }
    if (message.localBytes == null && existing.localBytes != null) {
      message = message.copyWith(localBytes: existing.localBytes);
    }
  }
  var i = 0;
  if (!message.isPending) {
    while (i < rest.length && rest[i].isPending) {
      i++;
    }
    while (i < rest.length && _isNewer(rest[i], message)) {
      i++;
    }
  }
  rest.insert(i, message);
  return rest;
}

/// Newest confirmed message (cursor for catching up after a reconnect).
ChatMessage? newestConfirmed(List<ChatMessage> newestFirst) {
  for (final m in newestFirst) {
    if (!m.isPending) return m;
  }
  return null;
}

// -----------------------------------------------------------------------------
// Timeline: bubble grouping + day separators
// -----------------------------------------------------------------------------

/// Messages from the same sender closer than this form one visual group.
const messageGroupGap = Duration(minutes: 5);

/// Calendar day in Bangladesh time (the product's notion of "today").
DateTime bdDay(DateTime instant) {
  final d = BdTime.toBd(instant);
  return DateTime.utc(d.year, d.month, d.day);
}

enum DayLabelKind { today, yesterday, date }

DayLabelKind dayLabelKind(DateTime day, DateTime today) {
  final diff = today.difference(day).inDays;
  if (diff == 0) return DayLabelKind.today;
  if (diff == 1) return DayLabelKind.yesterday;
  return DayLabelKind.date;
}

@immutable
sealed class TimelineEntry {
  const TimelineEntry();
}

/// A message plus its position inside a sender group.
@immutable
final class MessageEntry extends TimelineEntry {
  const MessageEntry({required this.message, required this.isFirstInGroup, required this.isLastInGroup});

  final ChatMessage message;

  /// Visually the top bubble of its group (show the sender name here).
  final bool isFirstInGroup;

  /// Visually the bottom bubble of its group (show avatar/time here).
  final bool isLastInGroup;
}

/// "আজ / গতকাল / 4 October" divider; [anchor] is an instant on that day.
@immutable
final class DayEntry extends TimelineEntry {
  const DayEntry({required this.day, required this.anchor});
  final DateTime day;
  final DateTime anchor;
}

bool _sameGroup(ChatMessage a, ChatMessage b) {
  if (a.isSystem || b.isSystem) return false;
  if (a.senderId != b.senderId) return false;
  if (bdDay(a.createdAt) != bdDay(b.createdAt)) return false;
  return a.createdAt.difference(b.createdAt).abs() <= messageGroupGap;
}

/// Builds the entries for a reversed ListView (index 0 = newest, at the
/// bottom). A day separator follows (= sits visually above) the oldest
/// message of each day. O(n).
List<TimelineEntry> buildTimeline(List<ChatMessage> newestFirst) {
  final out = <TimelineEntry>[];
  for (var i = 0; i < newestFirst.length; i++) {
    final m = newestFirst[i];
    final newer = i > 0 ? newestFirst[i - 1] : null;
    final older = i + 1 < newestFirst.length ? newestFirst[i + 1] : null;
    out.add(
      MessageEntry(
        message: m,
        isFirstInGroup: older == null || !_sameGroup(m, older),
        isLastInGroup: newer == null || !_sameGroup(m, newer),
      ),
    );
    final day = bdDay(m.createdAt);
    if (older == null || bdDay(older.createdAt) != day) {
      out.add(DayEntry(day: day, anchor: m.createdAt));
    }
  }
  return out;
}

// -----------------------------------------------------------------------------
// Read receipts
// -----------------------------------------------------------------------------

@immutable
class SeenInfo {
  const SeenInfo({required this.messageId, required this.seenBy, required this.others});

  /// The newest message I sent that is confirmed by the server.
  final String messageId;

  /// How many other members have read up to (or past) it.
  final int seenBy;
  final int others;

  bool get isSeen => seenBy > 0;
}

/// Read state of my newest confirmed message, from the other members'
/// `last_read_at`. Null when I have not sent anything visible.
SeenInfo? computeSeen(List<ChatMessage> newestFirst, String myId, Map<String, DateTime?> othersLastRead) {
  for (final m in newestFirst) {
    if (m.isSystem) continue;
    // Someone replied after my last message: they have obviously seen it,
    // and a receipt far up the list is just noise.
    if (m.senderId != myId) return null;
    if (m.isPending) continue;
    var seen = 0;
    for (final at in othersLastRead.values) {
      if (at != null && !at.isBefore(m.createdAt)) seen++;
    }
    return SeenInfo(messageId: m.id, seenBy: seen, others: othersLastRead.length);
  }
  return null;
}

// -----------------------------------------------------------------------------
// Inbox patching from Realtime `conversations` UPDATE rows
// -----------------------------------------------------------------------------

/// Applies a Realtime row to the inbox without refetching: patches the tile
/// and moves it to the top when it has a newer message. Returns null when
/// the conversation is not loaded (caller falls back to a refresh).
List<ConversationSummary>? applyConversationUpdate(
  List<ConversationSummary> items,
  Map<String, dynamic> row, {
  required String? myId,
  String? activeConversationId,
}) {
  final id = row['id']?.toString();
  if (id == null) return items;
  final index = items.indexWhere((c) => c.id == id);
  if (index < 0) return null;
  final current = items[index];
  final lastAt = row['last_message_at'] == null ? null : DateTime.tryParse(row['last_message_at'].toString());
  final sender = row['last_message_sender']?.toString();
  final isNewMessage = lastAt != null && (current.lastMessageAt == null || lastAt.isAfter(current.lastMessageAt!));

  var unread = current.unreadCount;
  if (isNewMessage) {
    if (sender == myId || id == activeConversationId) {
      unread = 0;
    } else {
      unread = current.unreadCount + 1;
    }
  }
  final patched = current.copyWith(
    title: row['title']?.toString(),
    avatarUrl: row['avatar_url']?.toString(),
    lastMessageAt: isNewMessage ? lastAt : null,
    lastMessagePreview: isNewMessage ? row['last_message_preview']?.toString() : null,
    lastMessageSender: isNewMessage ? sender : null,
    unreadCount: unread,
  );
  if (!isNewMessage) {
    return [
      for (final c in items)
        if (c.id == id) patched else c,
    ];
  }
  return [
    patched,
    for (final c in items)
      if (c.id != id) c,
  ];
}

/// Case-insensitive local filter for the inbox search box.
List<ConversationSummary> filterConversations(
  List<ConversationSummary> items,
  String query, {
  required String Function(ConversationSummary c) nameOf,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return items;
  return [
    for (final c in items)
      if (nameOf(c).toLowerCase().contains(q) ||
          (c.otherUser?.username.toLowerCase().contains(q) ?? false) ||
          (c.lastMessagePreview?.toLowerCase().contains(q) ?? false))
        c,
  ];
}

// -----------------------------------------------------------------------------
// Compact inbox timestamps
// -----------------------------------------------------------------------------

enum InboxTimeUnit { justNow, minutes, hours, yesterday, days, date }

/// Bucket for the compact time on an inbox tile ("৫ মি.", "গতকাল", "৪ অক্টো").
(InboxTimeUnit, int) inboxTime(DateTime at, DateTime now) {
  final diff = now.difference(at);
  if (diff.inMinutes < 1) return (InboxTimeUnit.justNow, 0);
  if (diff.inMinutes < 60) return (InboxTimeUnit.minutes, diff.inMinutes);
  final dayDiff = bdDay(now).difference(bdDay(at)).inDays;
  if (dayDiff == 0) return (InboxTimeUnit.hours, diff.inHours);
  if (dayDiff == 1) return (InboxTimeUnit.yesterday, 1);
  if (dayDiff < 7) return (InboxTimeUnit.days, dayDiff);
  return (InboxTimeUnit.date, 0);
}
