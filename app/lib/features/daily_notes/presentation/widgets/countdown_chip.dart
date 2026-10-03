import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/bd_time.dart';
import 'package:prostuti/features/daily_notes/application/countdown.dart';
import 'package:prostuti/features/daily_notes/presentation/widgets/note_category_style.dart';

/// "আজ রাত ১২টায় নোটগুলো সরিয়ে নেওয়া হবে · আর ৫ ঘণ্টা ২৩ মিনিট বাকি".
///
/// Ticks once a minute, aligned to the wall-clock minute, and calls
/// [onDayEnded] once when the Bangladesh day is over.
class RemovalCountdownChip extends StatefulWidget {
  const RemovalCountdownChip({this.onDayEnded, super.key});

  final VoidCallback? onDayEnded;

  @override
  State<RemovalCountdownChip> createState() => _RemovalCountdownChipState();
}

class _RemovalCountdownChipState extends State<RemovalCountdownChip> {
  Timer? _timer;
  late Duration _remaining;
  bool _endedFired = false;

  @override
  void initState() {
    super.initState();
    _remaining = BdTime.untilEndOfToday();
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(untilNextMinute(DateTime.now()), _tick);
  }

  void _tick() {
    if (!mounted) return;
    setState(() => _remaining = BdTime.untilEndOfToday());
    if (_remaining <= const Duration(seconds: 1)) {
      if (!_endedFired) {
        _endedFired = true;
        widget.onDayEnded?.call();
      }
    }
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final urgent = _remaining < const Duration(hours: 2);
    final color = urgent ? theme.colorScheme.error : readableWarning(theme.brightness);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: const BorderRadius.all(Radii.md),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(Icons.timer_outlined, size: 20, color: color),
            Gap.w8,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.dailyNotesRemovalNotice, style: theme.textTheme.bodySmall),
                  Text(
                    formatCountdown(_remaining, l, bangla: context.isBn),
                    style: theme.textTheme.labelLarge?.copyWith(color: color, fontWeight: FontWeight.w700),
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
