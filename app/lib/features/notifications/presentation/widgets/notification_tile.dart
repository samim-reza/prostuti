import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/features/notifications/data/app_notification.dart';

/// Icon + accent colour per notification type.
({IconData icon, Color color}) notificationStyle(String type, ColorScheme scheme) => switch (type) {
  'friend_request' => (icon: Icons.person_add_alt_1_rounded, color: AppColors.info),
  'friend_accept' => (icon: Icons.how_to_reg_rounded, color: AppColors.success),
  'post_reaction' => (icon: Icons.favorite_rounded, color: AppColors.accent),
  'post_comment' => (icon: Icons.mode_comment_rounded, color: scheme.primary),
  'comment_reply' => (icon: Icons.reply_rounded, color: scheme.tertiary),
  'daily_notes' => (icon: Icons.newspaper_rounded, color: scheme.primary),
  'daily_exam' => (icon: Icons.quiz_rounded, color: AppColors.warning),
  'routine' => (icon: Icons.wb_sunny_rounded, color: AppColors.gold),
  'plan_update' => (icon: Icons.event_repeat_rounded, color: AppColors.info),
  'addon' => (icon: Icons.workspace_premium_rounded, color: AppColors.gold),
  _ => (icon: Icons.campaign_rounded, color: scheme.primary),
};

/// One inbox row; unread rows are tinted and carry a dot.
class NotificationTile extends StatelessWidget {
  const NotificationTile({required this.notification, required this.onTap, super.key});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bangla = context.isBn;
    final style = notificationStyle(n.type, scheme);
    final unread = !n.isRead;
    final body = n.bodyFor(bangla: bangla);

    return Material(
      color: unread ? scheme.primary.withValues(alpha: 0.07) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: style.color.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: Icon(style.icon, color: style.color, size: 22),
              ),
              Gap.w12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.titleFor(bangla: bangla),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    if (body != null && body.trim().isNotEmpty) ...[
                      Gap.h4,
                      Text(
                        body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.4,
                          color: unread ? scheme.onSurface : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    Gap.h4,
                    Text(
                      Fmt.timeAgo(n.createdAt, bangla: bangla),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: unread ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (unread)
                Padding(
                  padding: const EdgeInsets.only(left: Gap.sm, top: Gap.xs),
                  child: Semantics(
                    label: context.l10n.notificationsUnread,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
