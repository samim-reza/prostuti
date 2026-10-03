import 'package:flutter/material.dart';
import 'package:prostuti/core/entitlements/feature_access.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/chat/data/chat_repository.dart';

/// Chat business error codes raised by Postgres → localized text.
String? chatErrorText(BuildContext context, String code) {
  final l = context.l10n;
  return switch (code) {
    'messaging_friends_only' => l.chatErrorFriendsOnly,
    'user_unavailable' => l.chatErrorUserUnavailable,
    'user_not_found' => l.chatErrorUserNotFound,
    'cannot_message_self' => l.chatErrorSelf,
    'title_required' => l.chatErrorTitleRequired,
    'too_many_members' => l.chatErrorTooManyMembers(context.n(ChatRepository.maxGroupMembers)),
    'conversation_not_found' => l.chatErrorConversationMissing,
    _ => null,
  };
}

/// Registers [chatErrorText] with core `failureMessage` (idempotent: the
/// top-level tear-off is canonical, so it is only added once).
void registerChatFailureMessages() => registerFailureMessages(chatErrorText);

/// Like `failureMessage`, but also resolves chat codes that core maps to a
/// generic text (`messaging_friends_only` / `user_unavailable` arrive as
/// PT403 → PermissionFailure, `user_not_found` as PT404 → NotFoundFailure).
String chatFailureMessage(BuildContext context, Object error) {
  final failure = AppFailure.from(error);
  if (failure is RateLimitFailure) return context.l10n.chatErrorRateLimited;
  return chatErrorText(context, failure.code) ?? failureMessage(context, failure);
}

/// Snack bar (or the upsell sheet for locked features) for a chat error.
void showChatError(BuildContext context, Object error) {
  final failure = AppFailure.from(error);
  if (failure is FeatureLockedFailure) {
    showLockedSheet(context);
    return;
  }
  showInfoSnack(context, chatFailureMessage(context, failure));
}
