import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/utils/json.dart';
import 'package:prostuti/features/feed/data/post.dart';

/// Rich block for non-text posts (exam result, shared note, achievement).
class PostAttachment extends StatelessWidget {
  const PostAttachment({required this.post, required this.isMine, super.key});

  final Post post;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return switch (post.kind) {
      PostKind.examResult => ExamResultCard(meta: post.examResult!, canOpen: isMine),
      PostKind.noteShare => _NoteShareCard(meta: post.meta),
      PostKind.achievement => _AchievementCard(meta: post.meta),
      PostKind.text => const SizedBox.shrink(),
    };
  }
}

/// Score card built from an `exam_result` post's server-generated meta.
class ExamResultCard extends StatelessWidget {
  const ExamResultCard({required this.meta, this.canOpen = false, super.key});

  final ExamResultMeta meta;

  /// Only the author can open their own session's result screen.
  final bool canOpen;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bn = context.isBn;
    final percent = (meta.ratio * 100).round();
    final card = Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        borderRadius: Radii.card,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer, scheme.secondaryContainer.withValues(alpha: 0.7)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events_rounded, size: 18, color: scheme.onPrimaryContainer),
              Gap.w8,
              Text(
                l.feedExamResultTitle,
                style: theme.textTheme.labelLarge?.copyWith(color: scheme.onPrimaryContainer),
              ),
            ],
          ),
          if (meta.title.isNotEmpty) ...[
            Gap.h4,
            Text(
              meta.title,
              style: theme.textTheme.titleMedium?.copyWith(color: scheme.onPrimaryContainer),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          Gap.h12,
          Row(
            children: [
              SizedBox.square(
                dimension: 76,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: meta.ratio,
                      strokeWidth: 7,
                      strokeCap: StrokeCap.round,
                      backgroundColor: scheme.surface.withValues(alpha: 0.6),
                      color: scheme.primary,
                    ),
                    Center(
                      child: Text(
                        Fmt.percent(percent, bangla: bn),
                        style: theme.textTheme.titleMedium?.copyWith(color: scheme.onPrimaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
              Gap.w16,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.feedExamScore, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onPrimaryContainer)),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: Fmt.score(meta.score, bangla: bn),
                            style: theme.textTheme.headlineSmall?.copyWith(color: scheme.onPrimaryContainer),
                          ),
                          TextSpan(
                            text: '  ${l.feedExamOutOf(Fmt.score(meta.maxScore, bangla: bn))}',
                            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onPrimaryContainer),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Gap.h12,
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              _StatPill(
                icon: Icons.check_circle_rounded,
                color: AppColors.success,
                label: l.feedExamCorrect,
                value: meta.correct,
              ),
              _StatPill(icon: Icons.cancel_rounded, color: AppColors.danger, label: l.feedExamWrong, value: meta.wrong),
              _StatPill(icon: Icons.quiz_rounded, color: scheme.primary, label: l.feedExamTotal, value: meta.total),
            ],
          ),
        ],
      ),
    );
    final sessionId = meta.sessionId;
    if (!canOpen || sessionId == null) return card;
    return Semantics(
      button: true,
      label: l.feedExamViewResult,
      child: InkWell(
        borderRadius: Radii.card,
        onTap: () => unawaited(context.push(Routes.examResult(sessionId))),
        child: card,
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.icon, required this.color, required this.label, required this.value});

  final IconData icon;
  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.xs + 2),
      decoration: BoxDecoration(color: theme.colorScheme.surface.withValues(alpha: 0.75), borderRadius: Radii.chip),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          Gap.w4,
          Text('$label ${context.n(value)}', style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _NoteShareCard extends StatelessWidget {
  const _NoteShareCard({required this.meta});

  final Map<String, dynamic> meta;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = meta.strOrNull('title');
    final summary = meta.strOrNull('summary') ?? meta.strOrNull('excerpt');
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: Radii.card,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => unawaited(context.push(Routes.notes)),
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(Gap.sm + 2),
                decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: Radii.button),
                child: Icon(Icons.article_rounded, color: scheme.onTertiaryContainer),
              ),
              Gap.w12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.feedNoteShare, style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    if (title != null)
                      Text(title, style: theme.textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (summary != null) ...[
                      Gap.h4,
                      Text(
                        summary,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    Gap.h4,
                    Text(l.feedOpenNotes, style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({required this.meta});

  final Map<String, dynamic> meta;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = meta.strOrNull('title');
    final description = meta.strOrNull('description') ?? meta.strOrNull('body');
    final value = meta.intOrNull('value') ?? meta.intOrNull('streak') ?? meta.intOrNull('count');
    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        borderRadius: Radii.card,
        color: AppColors.gold.withValues(alpha: 0.14),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.22), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: value == null
                ? const Icon(Icons.military_tech_rounded, color: AppColors.gold, size: 32)
                : Text(context.n(value), style: theme.textTheme.titleLarge?.copyWith(color: scheme.onSurface)),
          ),
          Gap.w16,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.feedAchievement, style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                if (title != null) Text(title, style: theme.textTheme.titleMedium),
                if (description != null)
                  Text(description, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
