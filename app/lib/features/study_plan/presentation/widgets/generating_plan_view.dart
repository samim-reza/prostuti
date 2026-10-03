import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';

/// "The AI is building your plan" state: a breathing sparkle and status lines
/// that rotate while the planner runs (it can take a while).
class GeneratingPlanView extends StatefulWidget {
  const GeneratingPlanView({this.compact = false, super.key});

  final bool compact;

  @override
  State<GeneratingPlanView> createState() => _GeneratingPlanViewState();
}

class _GeneratingPlanViewState extends State<GeneratingPlanView> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat(reverse: true);
  Timer? _timer;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 2200), (_) {
      if (mounted) setState(() => _step++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final steps = [
      l.studyPlanGenStep1,
      l.studyPlanGenStep2,
      l.studyPlanGenStep3,
      l.studyPlanGenStep4,
      l.studyPlanGenStep5,
    ];
    final size = widget.compact ? 64.0 : 96.0;
    return Semantics(
      liveRegion: true,
      label: l.studyPlanGenerating,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: Tween(begin: 0.9, end: 1.08).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [scheme.primary, scheme.tertiary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: 0.35), blurRadius: 24, spreadRadius: 2)],
              ),
              child: Icon(Icons.auto_awesome_rounded, color: scheme.onPrimary, size: size * 0.45),
            ),
          ),
          SizedBox(height: widget.compact ? Gap.md : Gap.xl),
          Text(l.studyPlanGenerating, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          Gap.h8,
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(anim),
                child: child,
              ),
            ),
            child: Text(
              steps[_step % steps.length],
              key: ValueKey(_step % steps.length),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          SizedBox(height: widget.compact ? Gap.md : Gap.lg),
          SizedBox(
            width: widget.compact ? 160 : 220,
            child: const ClipRRect(borderRadius: Radii.chip, child: LinearProgressIndicator(minHeight: 6)),
          ),
        ],
      ),
    );
  }
}
