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
import 'package:prostuti/features/exam/presentation/widgets/review_question_card.dart';
import 'package:prostuti/features/question_bank/application/practice_controller.dart';

/// One practice question: pick → instant verdict (green/red), explanation,
/// AI explanation; "show answer" before picking; bookmark & report.
class PracticeQuestionCard extends StatelessWidget {
  const PracticeQuestionCard({
    required this.question,
    required this.number,
    required this.outcome,
    required this.onSelect,
    required this.onReveal,
    super.key,
  });

  final Question question;
  final int number;
  final PracticeOutcome? outcome;
  final ValueChanged<int> onSelect;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final o = outcome;
    final resolved = o?.isResolved ?? false;
    final pending = o?.pending ?? false;
    final locked = o?.locked ?? false;
    final canAnswer = o == null;
    // Bookmark payload carries the answer once it is known.
    final bookmarkable = resolved
        ? question.withAnswer(correctIndex: o!.correctIndex, explanation: o.explanation, selectedIndex: o.selected)
        : question;

    OptionVisual visualOf(int i) {
      if (resolved) return reviewVisual(i, correctIndex: o!.correctIndex, selectedIndex: o.selected);
      if (pending && o!.selected == i) return OptionVisual.selected;
      return OptionVisual.idle;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.xs, Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                QuestionNumber(number: number),
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
                BookmarkQuestionButton(question: bookmarkable),
                ReportQuestionButton(questionId: question.id),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: Gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Gap.h4,
                  Text(question.stem, style: theme.textTheme.titleMedium),
                  Gap.h8,
                  QuestionSourceBadge(question: question),
                  Gap.h12,
                  for (var i = 0; i < question.options.length; i++) ...[
                    OptionTile(
                      label: optionLabel(i, language: question.language),
                      text: question.options[i],
                      visual: visualOf(i),
                      busy: pending && o!.selected == i,
                      onTap: canAnswer ? () => onSelect(i) : null,
                    ),
                    if (i < question.options.length - 1) Gap.h8,
                  ],
                  Gap.h12,
                  if (locked)
                    _Banner(icon: Icons.lock_clock_rounded, color: AppColors.warning, text: l.questionBankLocked)
                  else if (resolved) ...[
                    switch (o!.isCorrect) {
                      true => _Banner(
                        icon: Icons.check_circle_rounded,
                        color: AppColors.success,
                        text: l.questionBankCorrect,
                      ),
                      false => _Banner(
                        icon: Icons.cancel_rounded,
                        color: theme.colorScheme.error,
                        text: l.questionBankIncorrect,
                      ),
                      null => _Banner(
                        icon: Icons.visibility_rounded,
                        color: theme.colorScheme.primary,
                        text: l.questionBankRevealed,
                      ),
                    },
                    Gap.h12,
                    ExplanationBox(text: o.explanation),
                  ] else
                    Text(
                      l.questionBankPickHint,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (canAnswer)
                  TextButton.icon(
                    onPressed: onReveal,
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: Text(l.questionBankShowAnswer),
                    style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  ),
                if (resolved) AiExplainButton(question: question),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: Radii.button),
        child: Row(
          children: [
            Icon(icon, color: color),
            Gap.w8,
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color)),
            ),
          ],
        ),
      ),
    );
  }
}
