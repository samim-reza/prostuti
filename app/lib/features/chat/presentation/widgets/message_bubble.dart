import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/app_image.dart';
import 'package:prostuti/features/chat/application/chat_logic.dart';
import 'package:prostuti/features/chat/data/chat_models.dart';
import 'package:prostuti/features/chat/presentation/widgets/chat_format.dart';
import 'package:prostuti/features/chat/presentation/widgets/chat_image.dart';
import 'package:prostuti/features/profile/data/profile.dart';

const _big = Radius.circular(18);
const _small = Radius.circular(5);

/// One chat message: grouped corners, sender name/avatar in groups, reply
/// quote, image, deleted/system variants, delivery & read status.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.entry,
    required this.isMine,
    required this.isGroup,
    required this.onLongPress,
    required this.onReply,
    required this.onRetry,
    this.sender,
    this.replyTarget,
    this.replyAuthorName,
    this.seen,
    this.offline = false,
    super.key,
  });

  final MessageEntry entry;
  final bool isMine;
  final bool isGroup;
  final UserSummary? sender;

  /// The quoted message (null when not loaded / not a reply).
  final ChatMessage? replyTarget;
  final String? replyAuthorName;

  /// Read state, only for my newest confirmed message.
  final SeenInfo? seen;
  final bool offline;
  final VoidCallback onLongPress;
  final VoidCallback onReply;
  final VoidCallback onRetry;

  ChatMessage get message => entry.message;

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) return _SystemMessage(text: systemText(context.l10n, message.body));
    final width = MediaQuery.sizeOf(context).width;
    final showAvatar = !isMine && isGroup;
    final canReply = !message.isPending && !message.isDeleted;

    return Padding(
      padding: EdgeInsets.fromLTRB(Gap.md, entry.isFirstInGroup ? Gap.sm : Gap.xxs, Gap.md, 0),
      child: Row(
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (showAvatar)
            Padding(
              padding: EdgeInsets.only(right: Gap.sm, bottom: entry.isLastInGroup ? 20 : 0),
              child: SizedBox(
                width: 28,
                child: entry.isLastInGroup
                    ? UserAvatar(name: sender?.displayName, url: sender?.avatarUrl, radius: 14)
                    : null,
              ),
            ),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width * 0.76),
              child: Column(
                crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (showAvatar && entry.isFirstInGroup)
                    Padding(
                      padding: const EdgeInsets.only(left: Gap.md, bottom: Gap.xxs),
                      child: Text(
                        sender?.displayName ?? context.l10n.chatUnknownUser,
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600),
                      ),
                    ),
                  SwipeToReply(
                    enabled: canReply,
                    onReply: onReply,
                    child: GestureDetector(
                      onLongPress: onLongPress,
                      onTap: message.status == MessageStatus.failed ? onRetry : null,
                      child: _BubbleBody(
                        message: message,
                        isMine: isMine,
                        isFirst: entry.isFirstInGroup,
                        isLast: entry.isLastInGroup,
                        replyTarget: replyTarget,
                        replyAuthorName: replyAuthorName,
                      ),
                    ),
                  ),
                  _StatusLine(
                    message: message,
                    isMine: isMine,
                    isGroup: isGroup,
                    showTime: entry.isLastInGroup,
                    seen: seen,
                    offline: offline,
                    onRetry: onRetry,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BubbleBody extends StatelessWidget {
  const _BubbleBody({
    required this.message,
    required this.isMine,
    required this.isFirst,
    required this.isLast,
    this.replyTarget,
    this.replyAuthorName,
  });

  final ChatMessage message;
  final bool isMine;
  final bool isFirst;
  final bool isLast;
  final ChatMessage? replyTarget;
  final String? replyAuthorName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l = context.l10n;
    final radius = BorderRadius.only(
      topLeft: !isMine && !isFirst ? _small : _big,
      bottomLeft: !isMine && !isLast ? _small : _big,
      topRight: isMine && !isFirst ? _small : _big,
      bottomRight: isMine && !isLast ? _small : _big,
    );

    if (message.isDeleted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block_rounded, size: 16, color: scheme.onSurfaceVariant),
            Gap.w8,
            Flexible(
              child: Text(
                l.chatDeletedMessage,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final background = isMine ? scheme.primary : scheme.surfaceContainerHighest;
    final foreground = isMine ? scheme.onPrimary : scheme.onSurface;
    final quote = message.replyToId == null
        ? null
        : _ReplyQuote(target: replyTarget, authorName: replyAuthorName, onBubble: true, isMine: isMine);

    if (message.isImage) {
      return Semantics(
        image: true,
        label: l.chatPhotoSemantics,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: background, borderRadius: radius),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (quote != null) Padding(padding: const EdgeInsets.fromLTRB(6, 6, 6, 6), child: quote),
              GestureDetector(
                onTap: () => ChatImageViewer.open(context, path: message.mediaPath, localBytes: message.localBytes),
                child: ClipRRect(
                  borderRadius: radius.subtract(const BorderRadius.all(Radius.circular(3))),
                  child: Opacity(
                    opacity: message.status == MessageStatus.sending ? 0.7 : 1,
                    child: ChatImage(path: message.mediaPath, localBytes: message.localBytes),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
      decoration: BoxDecoration(color: background, borderRadius: radius),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (quote != null) ...[quote, Gap.h4],
          Text(message.body ?? '', style: theme.textTheme.bodyLarge?.copyWith(color: foreground, height: 1.45)),
        ],
      ),
    );
  }
}

/// Quoted message inside a bubble (or above the composer).
class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({required this.target, required this.authorName, required this.onBubble, required this.isMine});

  final ChatMessage? target;
  final String? authorName;
  final bool onBubble;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l = context.l10n;
    final accent = onBubble && isMine ? scheme.onPrimary : scheme.primary;
    final text = onBubble && isMine ? scheme.onPrimary.withValues(alpha: 0.85) : scheme.onSurfaceVariant;
    final t = target;
    return Container(
      padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.xs, Gap.sm, Gap.xs),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: const BorderRadius.all(Radii.sm),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (t != null && authorName != null)
            Text(
              authorName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(color: accent, fontWeight: FontWeight.w700),
            ),
          Text(
            t == null ? l.chatOriginalUnavailable : messageSnippet(l, t),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: text, height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// Time + delivery status under the last bubble of a group (and under any
/// pending/failed bubble).
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.message,
    required this.isMine,
    required this.isGroup,
    required this.showTime,
    required this.seen,
    required this.offline,
    required this.onRetry,
  });

  final ChatMessage message;
  final bool isMine;
  final bool isGroup;
  final bool showTime;
  final SeenInfo? seen;
  final bool offline;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.2);

    if (message.status == MessageStatus.failed) {
      return InkWell(
        onTap: onRetry,
        borderRadius: Radii.chip,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.xs, vertical: Gap.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 14, color: scheme.error),
              Gap.w4,
              Flexible(
                child: Text(l.chatFailed, style: style?.copyWith(color: scheme.error)),
              ),
            ],
          ),
        ),
      );
    }
    if (message.status == MessageStatus.sending) {
      return Padding(
        padding: const EdgeInsets.only(top: Gap.xxs, left: Gap.xs, right: Gap.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded, size: 13, color: scheme.onSurfaceVariant),
            Gap.w4,
            Text(offline ? l.chatWaitingForNetwork : l.chatSending, style: style),
          ],
        ),
      );
    }

    final s = seen;
    final parts = <String>[
      if (showTime || s != null) Fmt.time(message.createdAt, bangla: context.isBn),
      if (message.editedAt != null && !message.isDeleted) l.chatEdited,
      if (s != null && !s.isSeen) l.chatSent,
      if (s != null && s.isSeen && isGroup) l.chatSeenBy(context.n(s.seenBy)),
      if (s != null && s.isSeen && !isGroup) l.chatSeen,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Gap.xxs, left: Gap.xs, right: Gap.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(parts.join(' · '), style: style),
          if (s != null) ...[
            Gap.w4,
            Icon(
              s.isSeen ? Icons.done_all_rounded : Icons.done_rounded,
              size: 14,
              color: s.isSeen ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
  }
}

class _SystemMessage extends StatelessWidget {
  const _SystemMessage({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.xl, vertical: Gap.sm),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.xs),
          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHigh, borderRadius: Radii.chip),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// "আজ" / "গতকাল" / date divider between days.
class DaySeparator extends StatelessWidget {
  const DaySeparator({required this.entry, super.key});
  final DayEntry entry;

  @override
  Widget build(BuildContext context) => _SystemMessage(text: dayLabel(context, entry));
}

/// Composer banner: which message is being replied to.
class ReplyPreviewBar extends StatelessWidget {
  const ReplyPreviewBar({required this.message, required this.authorName, required this.onCancel, super.key});

  final ChatMessage message;
  final String authorName;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.xs, Gap.xs),
        child: Row(
          children: [
            Icon(Icons.reply_rounded, color: scheme.primary),
            Gap.w12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l.chatReplyingTo(authorName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
                  ),
                  Text(
                    messageSnippet(l, message),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton(tooltip: l.chatCancelReplyTooltip, icon: const Icon(Icons.close_rounded), onPressed: onCancel),
          ],
        ),
      ),
    );
  }
}

/// Drag a bubble to the right to reply (with a fading reply icon); springs
/// back on release.
class SwipeToReply extends StatefulWidget {
  const SwipeToReply({required this.child, required this.onReply, this.enabled = true, super.key});

  final Widget child;
  final VoidCallback onReply;
  final bool enabled;

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> with SingleTickerProviderStateMixin {
  static const _trigger = 56.0;
  static const _max = 76.0;

  late final AnimationController _back = AnimationController(vsync: this, duration: const Duration(milliseconds: 180))
    ..addListener(() => setState(() => _dx = _releasedAt * (1 - Curves.easeOut.transform(_back.value))));
  double _dx = 0;
  double _releasedAt = 0;

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final progress = (_dx / _trigger).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _back.stop(),
      onHorizontalDragUpdate: (d) => setState(() => _dx = (_dx + d.delta.dx).clamp(0.0, _max)),
      onHorizontalDragEnd: (_) {
        if (_dx >= _trigger) widget.onReply();
        _releasedAt = _dx;
        _back.forward(from: 0).ignore();
      },
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerLeft,
        children: [
          if (_dx > 0)
            Positioned(
              left: -4,
              child: Opacity(
                opacity: progress,
                child: Transform.scale(
                  scale: 0.6 + 0.4 * progress,
                  child: Icon(Icons.reply_rounded, color: Theme.of(context).colorScheme.primary),
                ),
              ),
            ),
          Transform.translate(offset: Offset(_dx, 0), child: widget.child),
        ],
      ),
    );
  }
}

/// Animated "…" bubble shown while someone is typing.
class TypingBubble extends StatefulWidget {
  const TypingBubble({this.label, super.key});

  /// Accessible description ("রহিম লিখছেন…").
  final String? label;

  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      label: widget.label,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.xs),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.all(_big),
            ),
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: 5),
                    Opacity(
                      opacity: 0.35 + 0.65 * _pulse((_c.value - i * 0.18) % 1),
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(color: scheme.onSurfaceVariant, shape: BoxShape.circle),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static double _pulse(double t) => t < 0.5 ? t * 2 : (1 - t) * 2;
}
