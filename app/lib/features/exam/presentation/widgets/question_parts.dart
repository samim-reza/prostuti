import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:url_launcher/url_launcher.dart';

/// "Where did this question come from?" — shown on every question card.
/// Falls back to the curated bank when the question has no `source_ref`.
class QuestionSourceBadge extends StatelessWidget {
  const QuestionSourceBadge({required this.question, super.key});

  final Question question;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final ref = question.sourceRef?.trim();
    final name = (ref == null || ref.isEmpty) ? l.examSourceCurated : ref;
    final year = question.year;
    final text = l.examSourceLabel(year == null ? name : '$name · ${context.n(year)}');
    final url = question.sourceUrl;
    final uri = url == null ? null : Uri.tryParse(url);
    final linkable = uri != null && (uri.scheme == 'https' || uri.scheme == 'http');

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm + 2, vertical: Gap.xs),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: 0.6), borderRadius: Radii.chip),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_outlined, size: 14, color: scheme.primary),
          Gap.w4,
          Flexible(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          if (linkable) ...[Gap.w4, Icon(Icons.open_in_new_rounded, size: 12, color: scheme.primary)],
        ],
      ),
    );
    if (!linkable) {
      return Semantics(
        label: text,
        child: ExcludeSemantics(child: content),
      );
    }
    return Tooltip(
      message: l.examSourceOpen,
      child: InkWell(
        borderRadius: Radii.chip,
        onTap: () => unawaited(launchUrl(uri, mode: LaunchMode.externalApplication)),
        child: content,
      ),
    );
  }
}

/// Subject name pill (resolved from the cached subject catalog).
class SubjectTag extends ConsumerWidget {
  const SubjectTag({required this.subjectId, super.key});

  final int subjectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subject = ref.watch(subjectByIdProvider(subjectId));
    if (subject == null) return const SizedBox.shrink();
    final color = subject.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.xxs),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: Radii.chip),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(subject.iconData, size: 13, color: color),
          Gap.w4,
          Flexible(
            child: Text(
              subject.name(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Easy / medium / hard indicator (difficulty 1–5).
class DifficultyPill extends StatelessWidget {
  const DifficultyPill({required this.difficulty, super.key});

  final int difficulty;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final (String label, Color color, int dots) = switch (difficulty) {
      <= 2 => (l.examDifficultyEasy, AppColors.success, 1),
      3 => (l.examDifficultyMedium, AppColors.warning, 2),
      _ => (l.examDifficultyHard, AppColors.danger, 3),
    };
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(color: i < dots ? color : color.withValues(alpha: 0.2), shape: BoxShape.circle),
            ),
          Gap.w4,
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// Numbered circle shown at the top-left of question cards.
class QuestionNumber extends StatelessWidget {
  const QuestionNumber({required this.number, this.color, super.key});

  final int number;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.primary;
    return Container(
      constraints: const BoxConstraints(minWidth: 30),
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: Radii.chip),
      child: Text(context.n(number), style: Theme.of(context).textTheme.labelLarge?.copyWith(color: c, height: 1.2)),
    );
  }
}

/// Tinted box with the official explanation.
class ExplanationBox extends StatelessWidget {
  const ExplanationBox({required this.text, this.title, super.key});

  final String? text;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final body = text?.trim();
    final empty = body == null || body.isEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.06),
        borderRadius: Radii.button,
        border: Border(left: BorderSide(color: scheme.primary, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded, size: 18, color: scheme.primary),
              Gap.w8,
              Text(title ?? l.examExplanation, style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          Gap.h4,
          Text(
            empty ? l.examNoExplanation : body,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: empty ? scheme.onSurfaceVariant : scheme.onSurface),
          ),
        ],
      ),
    );
  }
}
