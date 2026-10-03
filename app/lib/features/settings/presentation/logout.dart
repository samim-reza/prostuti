import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/offline_queue.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/settings/application/account_actions.dart';

/// Asks for confirmation (warning about unsynced offline changes) and signs
/// out. Shared by the profile tab and the settings screen.
Future<void> confirmAndSignOut(BuildContext context, WidgetRef ref) async {
  final l = context.l10n;
  final pending = OfflineQueue.instance.pendingCount.value;
  final message = pending > 0
      ? '${l.settingsLogoutBody}\n\n${l.settingsLogoutPendingWarning(context.n(pending))}'
      : l.settingsLogoutBody;
  final ok = await confirmDialog(
    context,
    title: l.settingsLogoutTitle,
    message: message,
    confirmLabel: l.settingsLogout,
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  await signOut(ref);
}
