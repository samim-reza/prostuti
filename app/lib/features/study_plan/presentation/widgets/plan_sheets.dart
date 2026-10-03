import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';
import 'package:prostuti/features/study_plan/data/study_plan_repository.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/online_guard.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/plan_generation_ui.dart';

/// Reasons sent to `request_replan(p_reason)`.
const replanReasons = ['too_hard', 'too_easy', 'missed_days', 'schedule_changed', 'other'];

String replanReasonLabel(BuildContext context, String reason) {
  final l = context.l10n;
  return switch (reason) {
    'too_hard' => l.studyPlanReasonTooHard,
    'too_easy' => l.studyPlanReasonTooEasy,
    'missed_days' => l.studyPlanReasonMissed,
    'schedule_changed' => l.studyPlanReasonSchedule,
    _ => l.studyPlanReasonOther,
  };
}

/// Asks why, then queues a server-side re-plan.
Future<void> showReplanSheet(BuildContext context, WidgetRef ref) async {
  if (!ensureOnline(context)) return;
  final reason = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _ReplanSheet(),
  );
  if (reason == null || !context.mounted) return;
  try {
    await ref.read(studyPlanRepositoryProvider).requestReplan(reason);
    if (!context.mounted) return;
    showInfoSnack(context, context.l10n.studyPlanReplanQueued);
    refreshPlanDataLater(context);
  } on Object catch (e) {
    if (context.mounted) showErrorSnack(context, e);
  }
}

class _ReplanSheet extends StatefulWidget {
  const _ReplanSheet();

  @override
  State<_ReplanSheet> createState() => _ReplanSheetState();
}

class _ReplanSheetState extends State<_ReplanSheet> {
  String _reason = replanReasons.first;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.studyPlanReplanTitle, style: theme.textTheme.titleLarge),
            Gap.h4,
            Text(
              l.studyPlanReplanBody,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            Gap.h12,
            for (final r in replanReasons)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                shape: const RoundedRectangleBorder(borderRadius: Radii.button),
                selected: _reason == r,
                selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.08),
                leading: Icon(_reason == r ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded),
                title: Text(replanReasonLabel(context, r)),
                onTap: () => setState(() => _reason = r),
              ),
            Gap.h16,
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, _reason),
              icon: const Icon(Icons.auto_fix_high_rounded),
              label: Text(l.studyPlanReplanConfirm),
            ),
          ],
        ),
      ),
    );
  }
}

/// Changes `profiles.daily_study_minutes` and re-plans with the new budget.
Future<void> showDailyMinutesSheet(BuildContext context, WidgetRef ref, {required int current}) async {
  if (!ensureOnline(context)) return;
  final minutes = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (_) => DailyMinutesSheet(initial: current),
  );
  if (minutes == null || minutes == current || !context.mounted) return;
  try {
    await ref.read(currentProfileProvider.notifier).save({'daily_study_minutes': minutes});
    await ref.read(studyPlanRepositoryProvider).requestReplan('daily_minutes_changed');
    if (!context.mounted) return;
    showInfoSnack(context, context.l10n.studyPlanMinutesSaved);
    refreshPlanDataLater(context);
  } on Object catch (e) {
    if (context.mounted) showErrorSnack(context, e);
  }
}

class DailyMinutesSheet extends StatefulWidget {
  const DailyMinutesSheet({required this.initial, super.key});

  final int initial;

  @override
  State<DailyMinutesSheet> createState() => _DailyMinutesSheetState();
}

class _DailyMinutesSheetState extends State<DailyMinutesSheet> {
  late double _value = widget.initial.clamp(30, 480).toDouble();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final label = Fmt.minutes(_value.round(), bangla: context.isBn);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.studyPlanMinutesTitle, style: theme.textTheme.titleLarge),
            Gap.h4,
            Text(
              l.studyPlanMinutesBody,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            Gap.h24,
            Center(
              child: Text(label, style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.primary)),
            ),
            Slider(
              value: _value,
              min: 30,
              max: 480,
              divisions: 30,
              label: label,
              onChanged: (v) => setState(() => _value = v),
            ),
            Gap.h16,
            FilledButton(
              onPressed: () => Navigator.pop(context, _value.round()),
              child: Text(l.studyPlanMinutesConfirm),
            ),
          ],
        ),
      ),
    );
  }
}
