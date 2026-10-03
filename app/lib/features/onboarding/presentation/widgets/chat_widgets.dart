import 'package:flutter/material.dart';
import 'package:prostuti/core/theme/app_spacing.dart';

/// Gradient sparkle avatar of "প্রস্তুতি এআই".
class BotAvatar extends StatelessWidget {
  const BotAvatar({this.size = 32, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.tertiary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(Icons.auto_awesome_rounded, color: scheme.onPrimary, size: size * 0.55),
    );
  }
}

/// Chat bubble; bot messages sit left with the avatar, user replies right.
class ChatBubble extends StatelessWidget {
  const ChatBubble({required this.fromBot, required this.child, this.showAvatar = true, super.key});

  final bool fromBot;
  final bool showAvatar;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.78;
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: Gap.md + 2, vertical: Gap.sm + 2),
      decoration: BoxDecoration(
        color: fromBot ? scheme.surface : scheme.primary,
        border: fromBot ? Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)) : null,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(fromBot ? 4 : 18),
          bottomRight: Radius.circular(fromBot ? 18 : 4),
        ),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: fromBot ? scheme.onSurface : scheme.onPrimary),
        child: child,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.xs),
      child: Row(
        mainAxisAlignment: fromBot ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (fromBot) ...[if (showAvatar) const BotAvatar(size: 28) else const SizedBox(width: 28), Gap.w8],
          Flexible(child: bubble),
        ],
      ),
    );
  }
}

/// Three bouncing dots — the bot is typing.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return ChatBubble(
      fromBot: true,
      child: SizedBox(
        height: 18,
        width: 40,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 3; i++)
                Transform.translate(
                  offset: Offset(0, -4 * _bounce((_c.value - i * 0.18) % 1)),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.4 + 0.6 * _bounce((_c.value - i * 0.18) % 1)),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static double _bounce(double t) => t < 0.5 ? Curves.easeOut.transform(t * 2) : Curves.easeIn.transform((1 - t) * 2);
}
