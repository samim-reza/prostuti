import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/features/study_plan/data/plan_models.dart';
import 'package:prostuti/features/study_plan/data/readiness_models.dart';

/// Labels, icons and colours for plan enums — one place, used by Home,
/// the plan screens and onboarding.
extension PlanDayKindUi on PlanDayKind {
  String label(BuildContext context) {
    final l = context.l10n;
    return switch (this) {
      PlanDayKind.study => l.studyPlanKindStudy,
      PlanDayKind.revision => l.studyPlanKindRevision,
      PlanDayKind.weakTopicExam => l.studyPlanKindWeakTopicExam,
      PlanDayKind.modelTest => l.studyPlanKindModelTest,
      PlanDayKind.rest => l.studyPlanKindRest,
      PlanDayKind.other => l.studyPlanKindStudy,
    };
  }

  IconData get icon => switch (this) {
    PlanDayKind.study || PlanDayKind.other => Icons.auto_stories_rounded,
    PlanDayKind.revision => Icons.replay_rounded,
    PlanDayKind.weakTopicExam => Icons.track_changes_rounded,
    PlanDayKind.modelTest => Icons.assignment_rounded,
    PlanDayKind.rest => Icons.self_improvement_rounded,
  };

  Color color(ColorScheme scheme) => switch (this) {
    PlanDayKind.study || PlanDayKind.other => scheme.primary,
    PlanDayKind.revision => AppColors.info,
    PlanDayKind.weakTopicExam => AppColors.danger,
    PlanDayKind.modelTest => AppColors.warning,
    PlanDayKind.rest => AppColors.success,
  };
}

extension PlanItemTypeUi on PlanItemType {
  IconData get icon => switch (this) {
    PlanItemType.read => Icons.menu_book_rounded,
    PlanItemType.practice => Icons.edit_note_rounded,
    PlanItemType.exam => Icons.quiz_rounded,
    PlanItemType.revise => Icons.autorenew_rounded,
    PlanItemType.rest => Icons.spa_rounded,
    PlanItemType.other => Icons.task_alt_rounded,
  };

  String actionLabel(BuildContext context) {
    final l = context.l10n;
    return switch (this) {
      PlanItemType.read => l.studyPlanActionRead,
      PlanItemType.practice => l.studyPlanActionPractice,
      PlanItemType.exam => l.studyPlanActionExam,
      PlanItemType.revise => l.studyPlanActionRevise,
      PlanItemType.rest || PlanItemType.other => l.studyPlanActionOpen,
    };
  }
}

extension PlanDayStatusUi on PlanDayStatus {
  String label(BuildContext context) {
    final l = context.l10n;
    return switch (this) {
      PlanDayStatus.pending => l.studyPlanStatusPending,
      PlanDayStatus.partial => l.studyPlanStatusPartial,
      PlanDayStatus.done => l.studyPlanStatusDone,
      PlanDayStatus.missed => l.studyPlanStatusMissed,
    };
  }

  IconData get icon => switch (this) {
    PlanDayStatus.pending => Icons.radio_button_unchecked_rounded,
    PlanDayStatus.partial => Icons.timelapse_rounded,
    PlanDayStatus.done => Icons.check_circle_rounded,
    PlanDayStatus.missed => Icons.cancel_rounded,
  };

  Color color(ColorScheme scheme) => switch (this) {
    PlanDayStatus.pending => scheme.outline,
    PlanDayStatus.partial => AppColors.warning,
    PlanDayStatus.done => AppColors.success,
    PlanDayStatus.missed => scheme.error,
  };
}

extension SkillLevelUi on SkillLevel {
  String label(BuildContext context) {
    final l = context.l10n;
    return switch (this) {
      SkillLevel.beginner => l.studyPlanLevelBeginner,
      SkillLevel.intermediate => l.studyPlanLevelIntermediate,
      SkillLevel.advanced => l.studyPlanLevelAdvanced,
    };
  }

  Color get color => switch (this) {
    SkillLevel.beginner => AppColors.warning,
    SkillLevel.intermediate => AppColors.info,
    SkillLevel.advanced => AppColors.success,
  };

  IconData get icon => switch (this) {
    SkillLevel.beginner => Icons.signal_cellular_alt_1_bar_rounded,
    SkillLevel.intermediate => Icons.signal_cellular_alt_2_bar_rounded,
    SkillLevel.advanced => Icons.signal_cellular_alt_rounded,
  };
}

/// Date helpers that keep Bangla digits/month names in the Bangla UI.
abstract final class PlanFmt {
  static String date(BuildContext context, DateTime d, {bool withYear = true}) =>
      Fmt.date(d, bangla: context.isBn, withYear: withYear);

  static String weekdayShort(BuildContext context, DateTime d) => DateFormat.E(context.isBn ? 'bn' : 'en').format(d);

  static String dayNumber(BuildContext context, DateTime d) => context.n(d.day);

  static String minutes(BuildContext context, int minutes) => Fmt.minutes(minutes, bangla: context.isBn);
}

/// Small rounded label (day kind, status, level…).
class PlanPill extends StatelessWidget {
  const PlanPill({required this.label, required this.color, this.icon, this.dense = false, super.key});

  final String label;
  final Color color;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? Gap.sm : Gap.sm + 2, vertical: dense ? 1 : Gap.xxs + 1),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: Radii.chip),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: Gap.xs)],
          Flexible(
            child: Text(label, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class PlanKindBadge extends StatelessWidget {
  const PlanKindBadge({required this.kind, this.dense = false, super.key});

  final PlanDayKind kind;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = kind.color(Theme.of(context).colorScheme);
    return PlanPill(label: kind.label(context), color: color, icon: kind.icon, dense: dense);
  }
}

/// Section title with an optional trailing action.
class PlanSectionHeader extends StatelessWidget {
  const PlanSectionHeader({required this.title, this.icon, this.trailing, super.key});

  final String title;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: Gap.lg, bottom: Gap.sm),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 20, color: scheme.primary), Gap.w8],
          Expanded(
            child: Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Thin rounded progress bar.
class PlanProgressBar extends StatelessWidget {
  const PlanProgressBar({required this.value, this.color, this.height = 8, super.key});

  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0, 1)),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: height,
          color: color ?? scheme.primary,
          backgroundColor: (color ?? scheme.primary).withValues(alpha: 0.12),
        ),
      ),
    );
  }
}
