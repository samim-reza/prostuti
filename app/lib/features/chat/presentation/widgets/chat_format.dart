import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/utils/bd_time.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/features/chat/application/chat_logic.dart';
import 'package:prostuti/features/chat/data/chat_models.dart';

/// Server-generated Bangla strings (trigger previews, system messages) that
/// are localized on the client when the UI is in English.
const _serverPhotoPreview = '📷 ছবি';
const _serverGroupCreated = 'গ্রুপ তৈরি হয়েছে';
const _serverDeletedPreview = '🚫'; // set by the messages_after_soft_delete trigger

String conversationTitle(AppLocalizations l, ConversationSummary c) =>
    c.displayName ?? (c.isGroup ? l.chatGroupFallbackTitle : l.chatUnknownUser);

String detailTitle(AppLocalizations l, ConversationDetail d, String? myId) =>
    d.displayName(myId) ?? (d.isGroup ? l.chatGroupFallbackTitle : l.chatUnknownUser);

/// Localized system message text.
String systemText(AppLocalizations l, String? body) => switch (body) {
  _serverGroupCreated => l.chatSystemGroupCreated,
  null => '',
  _ => body,
};

/// Inbox preview: localized, prefixed with "আপনি: " for my own messages.
String previewText(AppLocalizations l, ConversationSummary c, String? myId) {
  final raw = c.lastMessagePreview ?? '';
  final text = switch (raw) {
    _serverPhotoPreview => '📷 ${l.chatPhoto}',
    _serverGroupCreated => l.chatSystemGroupCreated,
    _serverDeletedPreview => '🚫 ${l.chatDeletedMessage}',
    _ => raw.replaceAll('\n', ' '),
  };
  return c.lastMessageSender != null && c.lastMessageSender == myId ? '${l.chatYouPrefix}$text' : text;
}

/// One-line snippet of a message (reply quotes).
String messageSnippet(AppLocalizations l, ChatMessage m) {
  if (m.isDeleted) return l.chatDeletedMessage;
  if (m.isImage) return '📷 ${l.chatPhoto}';
  if (m.isSystem) return systemText(l, m.body);
  return (m.body ?? '').replaceAll('\n', ' ');
}

/// Compact time on inbox tiles: "এইমাত্র", "৫ মি.", "গতকাল", "৪ অক্টো".
String inboxTimeLabel(BuildContext context, DateTime at) {
  final l = context.l10n;
  final (unit, n) = inboxTime(at, DateTime.now());
  final count = context.n(n);
  return switch (unit) {
    InboxTimeUnit.justNow => l.chatTimeJustNow,
    InboxTimeUnit.minutes => l.chatTimeMinutes(count),
    InboxTimeUnit.hours => l.chatTimeHours(count),
    InboxTimeUnit.yesterday => l.chatYesterday,
    InboxTimeUnit.days => l.chatTimeDays(count),
    InboxTimeUnit.date => DateFormat('d MMM', context.isBn ? 'bn' : 'en').format(BdTime.toBd(at)),
  };
}

/// "আজ" / "গতকাল" / "৪ অক্টোবর" (year only when it differs).
String dayLabel(BuildContext context, DayEntry entry) {
  final l = context.l10n;
  final today = bdDay(DateTime.now());
  return switch (dayLabelKind(entry.day, today)) {
    DayLabelKind.today => l.chatToday,
    DayLabelKind.yesterday => l.chatYesterday,
    DayLabelKind.date => Fmt.date(entry.anchor, bangla: context.isBn, withYear: entry.day.year != today.year),
  };
}
