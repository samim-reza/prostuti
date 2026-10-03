import 'package:flutter/material.dart';
import 'package:prostuti/core/entitlements/feature_access.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/widgets/state_views.dart';

/// Localized text for the backend codes raised by the social RPCs
/// (`send_friend_request`, `react_to_post`, `get_or_create_direct_conversation` …).
/// Registered with [registerFailureMessages] so `failureMessage()` knows them.
String? socialFailureResolver(BuildContext context, String code) {
  final l = context.l10n;
  return switch (code) {
    'cannot_friend_self' => l.friendsErrorSelf,
    'cannot_block_self' => l.friendsErrorBlockSelf,
    'cannot_message_self' => l.friendsErrorMessageSelf,
    'user_unavailable' => l.friendsErrorUnavailable,
    'user_not_found' => l.friendsUserNotFound,
    'messaging_friends_only' => l.friendsErrorMessagingFriendsOnly,
    'request_not_found' => l.friendsErrorRequestGone,
    'post_not_found' => l.feedErrorPostNotFound,
    'invalid_parent' => l.feedErrorInvalidParent,
    'storage_error' => l.feedErrorUploadFailed,
    _ => null,
  };
}

/// Like `failureMessage`, but also resolves codes carried by permission /
/// not-found failures (`user_unavailable` is raised with PT403 and
/// `post_not_found` with PT404, which the core mapper renders generically).
String socialErrorMessage(BuildContext context, Object error) {
  final f = AppFailure.from(error);
  final specific = switch (f) {
    PermissionFailure() || NotFoundFailure() || ServerFailure() => socialFailureResolver(context, f.code),
    _ => null,
  };
  return specific ?? failureMessage(context, f);
}

/// Snack bar for a failed social action (locked features open the paywall).
void showSocialError(BuildContext context, Object error) {
  final f = AppFailure.from(error);
  if (f is FeatureLockedFailure) {
    showLockedSheet(context);
    return;
  }
  showInfoSnack(context, socialErrorMessage(context, f));
}

/// For actions that truly need the network (uploading images, search,
/// deleting, reporting…): returns false and explains why when offline.
bool ensureOnline(BuildContext context) {
  if (ConnectivityService.instance.isOnline) return true;
  showInfoSnack(context, context.l10n.offlineUnavailable);
  return false;
}
