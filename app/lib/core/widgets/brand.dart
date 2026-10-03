import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:prostuti/core/l10n/l10n.dart';

/// The Prostuti mark (rising sun over an open book), vector-rendered.
class ProstutiMark extends StatelessWidget {
  const ProstutiMark({this.size = 72, super.key});
  final double size;

  @override
  Widget build(BuildContext context) =>
      SvgPicture.asset('assets/images/logo_mark.svg', width: size, height: size, semanticsLabel: context.l10n.appName);
}

/// Mark inside the green app-icon tile + wordmark.
class ProstutiLogo extends StatelessWidget {
  const ProstutiLogo({this.size = 84, this.showWordmark = true, this.onDark = false, super.key});

  final double size;
  final bool showWordmark;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          padding: EdgeInsets.all(size * 0.12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF00956A), Color(0xFF004D38)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF006A4E).withValues(alpha: 0.28),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ProstutiMark(size: size * 0.76),
        ),
        if (showWordmark) ...[
          SizedBox(height: size * 0.18),
          Text(
            context.l10n.appName,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: onDark ? Colors.white : theme.colorScheme.primary,
              height: 1.2,
            ),
          ),
        ],
      ],
    );
  }
}
