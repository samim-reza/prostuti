import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/features/notifications/application/unread_notifications_count_provider.dart';

/// App-bar bell with the unread count (Bangla digits in the Bangla UI);
/// opens the notification center. Drop it into any `AppBar.actions`.
class NotificationBellButton extends ConsumerWidget {
  const NotificationBellButton({this.iconColor, super.key});

  final Color? iconColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadNotificationsCountProvider);
    final l = context.l10n;
    final label = count > 99 ? '${context.n(99)}+' : context.n(count);
    return IconButton(
      tooltip: count > 0 ? l.notificationsBellTooltipUnread(label) : l.notificationsBellTooltip,
      color: iconColor,
      onPressed: () => context.push(Routes.notifications),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(label),
        child: Icon(count > 0 ? Icons.notifications_rounded : Icons.notifications_none_rounded),
      ),
    );
  }
}
