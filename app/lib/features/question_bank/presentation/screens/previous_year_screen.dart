import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/exam/application/exam_failure_messages.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/exam/presentation/widgets/exam_launcher.dart';
import 'package:prostuti/features/question_bank/application/question_bank_providers.dart';
import 'package:prostuti/features/question_bank/data/question_bank_models.dart';
import 'package:prostuti/features/question_bank/data/question_bank_repository.dart';

/// Previous-exam papers; while none are published yet, an informative empty
/// state plus every other question source (practice or take as an exam).
class PreviousYearScreen extends ConsumerWidget {
  const PreviousYearScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    final repo = ref.read(questionBankRepositoryProvider);
    try {
      await Future.wait([repo.sources(kind: SourceKind.previousExam, force: true), repo.sources(force: true)]);
    } on Object {
      // Keep cached lists.
    }
    ref
      ..invalidate(previousExamSourcesProvider)
      ..invalidate(allSourcesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    registerExamFailureMessages();
    final l = context.l10n;
    final papers = ref.watch(previousExamSourcesProvider);
    final all = ref.watch(allSourcesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.questionBankPreviousTitle)),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl),
          children: [
            Text(l.questionBankPreviousPapers, style: theme.textTheme.titleMedium),
            Gap.h8,
            papers.when(
              skipLoadingOnRefresh: true,
              loading: () => const SkeletonCards(count: 1, height: 120),
              error: (e, _) =>
                  ErrorView(error: e, compact: true, onRetry: () => ref.invalidate(previousExamSourcesProvider)),
              data: (list) => list.isEmpty
                  ? const _ComingSoon()
                  : Column(
                      children: [
                        for (final s in list) ...[SourceCard(source: s), Gap.h8],
                      ],
                    ),
            ),
            Gap.h16,
            Text(l.questionBankOtherSources, style: theme.textTheme.titleMedium),
            Gap.h8,
            all.when(
              skipLoadingOnRefresh: true,
              loading: () => const SkeletonCards(count: 2, height: 120),
              error: (e, _) => ErrorView(error: e, compact: true, onRetry: () => ref.invalidate(allSourcesProvider)),
              data: (list) {
                final others = list.where((s) => s.kind != SourceKind.previousExam).toList();
                if (others.isEmpty) {
                  return EmptyView(compact: true, title: l.questionBankNoSources);
                }
                return Column(
                  children: [
                    for (final s in others) ...[SourceCard(source: s), Gap.h8],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Card(
      color: AppColors.gold.withValues(alpha: 0.10),
      child: Padding(
        padding: Gap.card,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.history_edu_rounded, size: 40, color: AppColors.gold),
            Gap.w12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.questionBankPreviousEmptyTitle, style: theme.textTheme.titleSmall),
                  Gap.h4,
                  Text(l.questionBankPreviousEmptyBody, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension SourceKindStyle on SourceKind {
  IconData get icon => switch (this) {
    SourceKind.previousExam => Icons.history_edu_rounded,
    SourceKind.book => Icons.menu_book_rounded,
    SourceKind.newspaper => Icons.newspaper_rounded,
    SourceKind.website => Icons.language_rounded,
    SourceKind.aiGenerated => Icons.auto_awesome_rounded,
    SourceKind.curated => Icons.verified_rounded,
  };

  String label(AppLocalizations l) => switch (this) {
    SourceKind.previousExam => l.questionBankSourcePrevious,
    SourceKind.book => l.questionBankSourceBook,
    SourceKind.newspaper => l.questionBankSourceNewspaper,
    SourceKind.website => l.questionBankSourceWebsite,
    SourceKind.aiGenerated => l.questionBankSourceAi,
    SourceKind.curated => l.questionBankSourceCurated,
  };
}

/// A question source with its count and "practice" / "take as exam".
class SourceCard extends ConsumerWidget {
  const SourceCard({required this.source, super.key});

  final QuestionSource source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final meta = [
      source.kind.label(l),
      if (source.year != null) context.n(source.year!),
      if (source.examType != null) source.examType!,
      if (source.publisher != null) source.publisher!,
    ].join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.12), borderRadius: Radii.button),
                  child: Icon(source.kind.icon, color: scheme.primary),
                ),
                Gap.w12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(source.name, style: theme.textTheme.titleSmall),
                      Text(
                        meta,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Gap.w8,
                Text(l.examQuestionsCount(context.n(source.questionCount)), style: theme.textTheme.labelLarge),
              ],
            ),
            Gap.h12,
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: () => context.push(Routes.practice(sourceId: source.id)),
                    icon: const Icon(Icons.edit_note_rounded),
                    label: Text(l.questionBankPractice, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
                Gap.w12,
                Expanded(
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: () => unawaited(
                      ExamLauncher.start(context, ref, ExamKind.previousYear, config: {'source_id': source.id}),
                    ),
                    icon: const Icon(Icons.timer_outlined),
                    label: Text(l.questionBankTakeExam, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
