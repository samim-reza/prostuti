import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/exam/presentation/utils/option_labels.dart';
import 'package:prostuti/features/exam/presentation/widgets/ai_explain_sheet.dart';
import 'package:prostuti/features/exam/presentation/widgets/option_tile.dart';
import 'package:prostuti/features/exam/presentation/widgets/question_actions.dart';
import 'package:prostuti/features/exam/presentation/widgets/question_parts.dart';

/// Visual for option [i] once the answer is known.
OptionVisual reviewVisual(int i, {required int? correctIndex, required int? selectedIndex}) {
  if (correctIndex == null) return i == selectedIndex ? OptionVisual.selected : OptionVisual.idle;
  if (i == correctIndex) return OptionVisual.correct;
  if (i == selectedIndex) return OptionVisual.wrong;
  return OptionVisual.muted;
}

/// A graded question: the user's choice (red when wrong), the correct answer
/// (green), explanation, source, AI explanation, bookmark and report.
class ReviewQuestionCard extends StatelessWidget {
  const ReviewQuestionCard({required this.question, this.number, this.subtitle, this.footer, super.key});

  final Question question;
  final int? number;

  /// Extra meta line under the header (e.g. "3 days ago").
  final String? subtitle;

  /// Extra actions appended to the bottom row.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final q = question;
    final correct = q.isCorrect;
    final (String status, Color color, IconData icon) = switch (correct) {
      true => (l.examResultCorrect, AppColors.success, Icons.check_circle_rounded),
      false => (l.examResultWrong, scheme.error, Icons.cancel_rounded),
      null => (l.examResultSkipped, scheme.outline, Icons.remove_circle_outline_rounded),
    };
    String labelOf(int? i) => i == null ? '—' : optionLabel(i, language: q.language);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.xs, Gap.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (number != null) ...[QuestionNumber(number: number!, color: color), Gap.w8],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.xxs),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: Radii.chip),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 14, color: color),
                      Gap.w4,
                      Text(status, style: theme.textTheme.labelSmall?.copyWith(color: color)),
                    ],
                  ),
                ),
                Gap.w8,
                Flexible(child: SubjectTag(subjectId: q.subjectId)),
                const Spacer(),
                BookmarkQuestionButton(question: q),
                ReportQuestionButton(questionId: q.id),
              ],
            ),
            if (subtitle != null)
              Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            Padding(
              padding: const EdgeInsets.only(right: Gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Gap.h4,
                  Text(q.stem, style: theme.textTheme.titleMedium),
                  Gap.h8,
                  QuestionSourceBadge(question: q),
                  Gap.h12,
                  for (var i = 0; i < q.options.length; i++) ...[
                    OptionTile(
                      label: optionLabel(i, language: q.language),
                      text: q.options[i],
                      visual: reviewVisual(i, correctIndex: q.correctIndex, selectedIndex: q.selectedIndex),
                    ),
                    if (i < q.options.length - 1) Gap.h8,
                  ],
                  Gap.h12,
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '${l.examReviewYourAnswer}: '),
                        TextSpan(
                          text: q.selectedIndex == null ? l.examReviewNotAnswered : labelOf(q.selectedIndex),
                          style: TextStyle(fontWeight: FontWeight.w700, color: color),
                        ),
                        const TextSpan(text: '   ·   '),
                        TextSpan(text: '${l.examReviewCorrectAnswer}: '),
                        TextSpan(
                          text: labelOf(q.correctIndex),
                          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.success),
                        ),
                      ],
                    ),
                    style: theme.textTheme.bodyMedium,
                  ),
                  Gap.h12,
                  ExplanationBox(text: q.explanation),
                ],
              ),
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AiExplainButton(question: q),
                ?footer,
              ],
            ),
          ],
        ),
      ),
    );
  }
}
