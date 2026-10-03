import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_colors.dart';

/// Animated 270° gauge for the readiness percentage (0–100).
class ReadinessGauge extends StatelessWidget {
  const ReadinessGauge({required this.value, this.size = 200, this.caption, super.key});

  final int value;
  final double size;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final target = value.clamp(0, 100) / 100;
    return Semantics(
      label: context.l10n.studyPlanReadinessSemantics(context.n(value)),
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: target),
          duration: const Duration(milliseconds: 1200),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => CustomPaint(
            painter: _GaugePainter(progress: v, track: scheme.surfaceContainerHighest),
            child: SizedBox.square(
              dimension: size,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${context.n((v * 100).round())}%',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: size * 0.2,
                        height: 1.1,
                      ),
                    ),
                    if (caption != null)
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: size * 0.18),
                        child: Text(
                          caption!,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.progress, required this.track});

  final double progress;
  final Color track;

  static const _start = math.pi * 0.75;
  static const _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.085;
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect, _start, _sweep, false, base);
    if (progress <= 0) return;
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        endAngle: _sweep,
        colors: [AppColors.accent, AppColors.gold, AppColors.success],
        transform: GradientRotation(_start),
      ).createShader(rect);
    canvas.drawArc(rect, _start, _sweep * progress, false, fg);
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.progress != progress || old.track != track;
}
