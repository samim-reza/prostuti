import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/paged_list_view.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/notifications/application/notifications_controller.dart';
import 'package:prostuti/features/notifications/application/unread_notifications_count_provider.dart';
import 'package:prostuti/features/notifications/data/app_notification.dart';
import 'package:prostuti/features/notifications/presentation/widgets/notification_tile.dart';

/// The notification center: live inbox, tap to open, swipe to delete,
/// "mark all as read". Works offline (cached page, queued actions).
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, AppNotification n) async {
    unawaited(ref.read(notificationsProvider.notifier).markRead(n));
    final route = notificationRoute(n.type, n.data);
    if (route != null) await context.push(route);
  }

  Future<void> _markAll(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    try {
      await ref.read(notificationsProvider.notifier).markAllRead();
      if (context.mounted) showInfoSnack(context, l.notificationsAllMarkedRead);
    } on Object catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, AppNotification n) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(notificationsProvider.notifier).delete(n);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.notificationsDeleted)));
    } on Object catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final state = ref.watch(notificationsProvider);
    final notifier = ref.read(notificationsProvider.notifier);
    final unreadCount = ref.watch(unreadNotificationsCountProvider);
    final hasUnread = unreadCount > 0 || state.items.any((n) => !n.isRead);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.notificationsTitle),
        actions: [
          IconButton(
            tooltip: l.notificationsMarkAllRead,
            onPressed: hasUnread ? () => unawaited(_markAll(context, ref)) : null,
            icon: const Icon(Icons.done_all_rounded),
          ),
        ],
      ),
      body: PagedListView<AppNotification>(
        state: state,
        padding: const EdgeInsets.only(bottom: Gap.xl),
        onLoadMore: () => unawaited(notifier.loadMore()),
        onRefresh: notifier.refresh,
        onRetry: () => unawaited(notifier.retry()),
        separator: const Divider(height: 1, indent: 72),
        empty: EmptyView(
          icon: Icons.notifications_none_rounded,
          title: l.notificationsEmptyTitle,
          message: l.notificationsEmptyMessage,
        ),
        itemBuilder: (context, n, _) => Dismissible(
          key: ValueKey('notification:${n.id}'),
          direction: DismissDirection.endToStart,
          background: ColoredBox(
            color: scheme.errorContainer,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: Gap.xl),
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: scheme.onErrorContainer,
                  semanticLabel: l.notificationsDeleteLabel,
                ),
              ),
            ),
          ),
          onDismissed: (_) => unawaited(_delete(context, ref, n)),
          child: NotificationTile(notification: n, onTap: () => unawaited(_open(context, ref, n))),
        ),
      ),
    );
  }
}
