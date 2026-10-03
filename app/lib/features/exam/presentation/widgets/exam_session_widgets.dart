import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/features/exam/application/exam_answers.dart';
import 'package:prostuti/features/exam/application/exam_clock.dart';
import 'package:prostuti/features/exam/application/exam_session_controller.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/exam/presentation/utils/option_labels.dart';
import 'package:prostuti/features/exam/presentation/widgets/option_tile.dart';
import 'package:prostuti/features/exam/presentation/widgets/question_parts.dart';

/// Countdown pill: neutral → amber (≤ 5 min) → red & pulsing (last minute).
/// Rebuilds only itself, once per second.
class ExamTimerChip extends StatelessWidget {
  const ExamTimerChip({required this.remaining, super.key});

  final ValueListenable<Duration> remaining;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bangla = context.isBn;
    return ValueListenableBuilder<Duration>(
      valueListenable: remaining,
      builder: (context, left, _) {
        final phase = ExamTiming.phaseOf(left);
        final (Color fg, Color bg) = switch (phase) {
          TimerPhase.normal => (scheme.primary, scheme.primary.withValues(alpha: 0.10)),
          TimerPhase.warning => (AppColors.warning, AppColors.warning.withValues(alpha: 0.15)),
          TimerPhase.critical || TimerPhase.expired => (scheme.error, scheme.error.withValues(alpha: 0.14)),
        };
        final text = ExamTiming.format(left, bangla: bangla);
        final critical = phase == TimerPhase.critical;
        return Semantics(
          liveRegion: critical,
          label: '${context.l10n.examTimeLeft}: $text',
          excludeSemantics: true,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.xs + 2),
            decoration: BoxDecoration(
              color: critical && left.inSeconds.isEven ? fg.withValues(alpha: 0.24) : bg,
              borderRadius: Radii.chip,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timer_outlined, size: 18, color: fg),
                Gap.w4,
                Text(
                  text,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: fg, fontFeatures: const [FontFeature.tabularFigures()], height: 1.2),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One exam question with bubble options; rebuilds only when *its* answer
/// or flag changes.
class ExamQuestionCard extends ConsumerWidget {
  const ExamQuestionCard({required this.sessionId, required this.question, required this.number, super.key});

  final String sessionId;
  final Question question;
  final int number;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final provider = examSessionControllerProvider(sessionId);
    final selected = ref.watch(provider.select((a) => a.value?.sheet.selectedFor(question.id)));
    final flagged = ref.watch(provider.select((a) => a.value?.sheet.isFlagged(question.id) ?? false));
    final locked = ref.watch(provider.select((a) => a.value?.isLocked ?? false));
    final scheme = Theme.of(context).colorScheme;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: Radii.card,
        side: BorderSide(
          color: flagged ? AppColors.warning : scheme.outlineVariant.withValues(alpha: 0.5),
          width: flagged ? 1.4 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.xs, Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                QuestionNumber(number: number, color: selected != null ? scheme.primary : scheme.onSurfaceVariant),
                Gap.w8,
                Expanded(
                  child: Wrap(
                    spacing: Gap.sm,
                    runSpacing: Gap.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SubjectTag(subjectId: question.subjectId),
                      DifficultyPill(difficulty: question.difficulty),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: flagged ? l.examUnflag : l.examFlag,
                  isSelected: flagged,
                  icon: const Icon(Icons.outlined_flag_rounded),
                  selectedIcon: const Icon(Icons.flag_rounded, color: AppColors.warning),
                  onPressed: locked ? null : () => ref.read(provider.notifier).toggleFlag(question.id),
                ),
              ],
            ),
            Gap.h8,
            Padding(
              padding: const EdgeInsets.only(right: Gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(question.stem, style: Theme.of(context).textTheme.titleMedium),
                  Gap.h8,
                  QuestionSourceBadge(question: question),
                  Gap.h12,
                  for (var i = 0; i < question.options.length; i++) ...[
                    OptionTile(
                      label: optionLabel(i, language: question.language),
                      text: question.options[i],
                      visual: selected == i ? OptionVisual.selected : OptionVisual.idle,
                      onTap: locked ? null : () => ref.read(provider.notifier).select(question.id, i),
                    ),
                    if (i < question.options.length - 1) Gap.h8,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grid of question numbers coloured by state; pops with the tapped index.
class QuestionNavigatorSheet extends ConsumerWidget {
  const QuestionNavigatorSheet({required this.sessionId, required this.questionIds, super.key});

  final String sessionId;
  final List<int> questionIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final sheet = ref.watch(examSessionControllerProvider(sessionId).select((a) => a.value?.sheet));
    if (sheet == null) return const SizedBox.shrink();
    final total = questionIds.length;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.examNavigator, style: Theme.of(context).textTheme.titleLarge),
            Gap.h4,
            Text(
              '${l.examAnsweredOf(context.n(sheet.answeredCount), context.n(total))} · '
              '${l.examFlaggedCount(context.n(sheet.flaggedCount))}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
            Gap.h12,
            Wrap(
              spacing: Gap.lg,
              runSpacing: Gap.xs,
              children: [
                _Legend(mark: QuestionMark.answered, label: l.examLegendAnswered),
                _Legend(mark: QuestionMark.unanswered, label: l.examLegendUnanswered),
                _Legend(mark: QuestionMark.flagged, label: l.examLegendFlagged),
              ],
            ),
            Gap.h16,
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 56,
                  mainAxisSpacing: Gap.sm,
                  crossAxisSpacing: Gap.sm,
                ),
                itemCount: total,
                itemBuilder: (context, i) =>
                    _Cell(number: i + 1, mark: sheet.markOf(questionIds[i]), onTap: () => Navigator.pop(context, i)),
              ),
            ),
            Gap.h8,
            Text(
              l.examNavigatorHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

({Color bg, Color fg, Color border}) _markColors(BuildContext context, QuestionMark mark) {
  final scheme = Theme.of(context).colorScheme;
  return switch (mark) {
    QuestionMark.answered => (bg: scheme.primary, fg: scheme.onPrimary, border: scheme.primary),
    QuestionMark.answeredFlagged => (bg: scheme.primary, fg: scheme.onPrimary, border: AppColors.warning),
    QuestionMark.flagged => (
      bg: AppColors.warning.withValues(alpha: 0.18),
      fg: scheme.onSurface,
      border: AppColors.warning,
    ),
    QuestionMark.unanswered => (bg: Colors.transparent, fg: scheme.onSurface, border: scheme.outlineVariant),
  };
}

class _Cell extends StatelessWidget {
  const _Cell({required this.number, required this.mark, required this.onTap});

  final int number;
  final QuestionMark mark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = _markColors(context, mark);
    final flagged = mark == QuestionMark.flagged || mark == QuestionMark.answeredFlagged;
    return Semantics(
      button: true,
      label: context.l10n.examQuestionNo(context.n(number)),
      child: Material(
        color: c.bg,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.button,
          side: BorderSide(color: c.border, width: flagged ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: Radii.button,
          onTap: onTap,
          child: Stack(
            children: [
              Center(
                child: Text(context.n(number), style: Theme.of(context).textTheme.labelLarge?.copyWith(color: c.fg)),
              ),
              if (flagged)
                const Positioned(right: 3, top: 3, child: Icon(Icons.flag_rounded, size: 11, color: AppColors.warning)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.mark, required this.label});
  final QuestionMark mark;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = _markColors(context, mark);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: const BorderRadius.all(Radius.circular(4)),
            border: Border.all(color: c.border, width: 1.4),
          ),
        ),
        Gap.w4,
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

/// Confirmation before submitting: answered vs skipped, flagged warning and
/// the negative-marking reminder.
Future<bool> showSubmitConfirmDialog(
  BuildContext context, {
  required int answered,
  required int total,
  required int flagged,
  required double negativeMark,
}) async {
  final l = context.l10n;
  final scheme = Theme.of(context).colorScheme;
  final skipped = (total - answered).clamp(0, total);
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.task_alt_rounded, color: scheme.primary, size: 32),
      title: Text(l.examSubmitTitle, textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _StatBox(label: l.examSubmitAnswered, value: ctx.n(answered), color: AppColors.success),
              ),
              Gap.w12,
              Expanded(
                child: _StatBox(label: l.examSubmitSkipped, value: ctx.n(skipped), color: scheme.outline),
              ),
            ],
          ),
          if (flagged > 0) ...[
            Gap.h12,
            Row(
              children: [
                const Icon(Icons.flag_rounded, size: 18, color: AppColors.warning),
                Gap.w8,
                Expanded(child: Text(l.examSubmitFlaggedWarn(ctx.n(flagged)))),
              ],
            ),
          ],
          Gap.h12,
          Text(
            l.examSubmitNegative(Fmt.score(negativeMark, bangla: ctx.isBn)),
            style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.examSubmitCancel)),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l.examSubmitConfirm),
        ),
      ],
    ),
  );
  return result ?? false;
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Gap.md),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: Radii.button),
      child: Column(
        children: [
          Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: color)),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}
