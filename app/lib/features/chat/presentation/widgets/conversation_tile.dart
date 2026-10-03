import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/app_image.dart';
import 'package:prostuti/features/chat/data/chat_models.dart';
import 'package:prostuti/features/chat/presentation/widgets/chat_format.dart';

/// Avatar of a conversation: the other user, a group photo or a group icon,
/// with an optional "online" dot.
class ConversationAvatar extends StatelessWidget {
  const ConversationAvatar({
    required this.isGroup,
    required this.name,
    this.url,
    this.radius = 26,
    this.online = false,
    super.key,
  });

  final bool isGroup;
  final String name;
  final String? url;
  final double radius;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget avatar = isGroup && (url == null || url!.isEmpty)
        ? CircleAvatar(
            radius: radius,
            backgroundColor: scheme.primaryContainer,
            child: Icon(Icons.groups_rounded, size: radius * 1.05, color: scheme.onPrimaryContainer),
          )
        : UserAvatar(name: name, url: url, radius: radius);
    if (!online) return avatar;
    final dot = radius * 0.5;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: dot,
            height: dot,
            decoration: BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
              border: Border.all(color: scheme.surface, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

/// One inbox row: avatar, name, last message, time, unread badge, muted icon.
class ConversationTile extends StatelessWidget {
  const ConversationTile({
    required this.conversation,
    required this.myId,
    required this.onTap,
    this.onLongPress,
    super.key,
  });

  final ConversationSummary conversation;
  final String? myId;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unread = c.unreadCount > 0;
    final title = conversationTitle(l, c);
    final lastAt = c.lastMessageAt;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
        child: Row(
          children: [
            ConversationAvatar(isGroup: c.isGroup, name: title, url: c.displayAvatar),
            Gap.w12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (c.muted) ...[
                        Gap.w4,
                        Icon(
                          Icons.notifications_off_outlined,
                          size: 15,
                          color: scheme.onSurfaceVariant,
                          semanticLabel: l.chatMutedLabel,
                        ),
                      ],
                      const Spacer(),
                      if (lastAt != null)
                        Text(
                          inboxTimeLabel(context, lastAt),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: unread && !c.muted ? scheme.primary : scheme.onSurfaceVariant,
                            fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  Gap.h4,
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          previewText(l, c, myId),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.3,
                            color: unread ? scheme.onSurface : scheme.onSurfaceVariant,
                            fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (unread) ...[Gap.w8, UnreadBadge(count: c.unreadCount, muted: c.muted)],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pill with the unread count (Bangla digits, capped at 99+).
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({required this.count, this.muted = false, super.key});

  final int count;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = count > 99 ? '${context.n(99)}+' : context.n(count);
    return Semantics(
      label: context.l10n.chatUnreadSemantics(label),
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 22),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: muted ? scheme.outline : scheme.primary, borderRadius: Radii.chip),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: muted ? scheme.surface : scheme.onPrimary, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
