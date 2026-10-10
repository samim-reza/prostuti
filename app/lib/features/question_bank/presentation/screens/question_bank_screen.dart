import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:prostuti/features/catalog/presentation/track_selector.dart';
import 'package:prostuti/features/exam/application/exam_failure_messages.dart';
import 'package:prostuti/features/question_bank/application/offline_packs.dart';
import 'package:prostuti/features/question_bank/presentation/widgets/offline_pack_widgets.dart';
import 'package:prostuti/features/question_bank/presentation/widgets/subject_widgets.dart';

/// Sections (BCS · bank · other jobs) with their subjects, marks in that
/// pattern, question counts, mastery and offline packs. Every question of
/// every source lives here (there is no separate previous-year list).
class QuestionBankScreen extends ConsumerWidget {
  const QuestionBankScreen({super.key});

  static Future<void> refreshSubjects(WidgetRef ref) async {
    try {
      await ref.read(catalogRepositoryProvider).subjects(force: true);
    } on Object {
      // Fall back to what is cached.
    }
    ref
      ..invalidate(subjectsProvider)
      ..invalidate(trackSubjectsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    registerExamFailureMessages();
    final l = context.l10n;
    final track = ref.watch(selectedTrackProvider);
    final subjects = ref.watch(trackSubjectsProvider(track));
    return Scaffold(
      appBar: AppBar(
        title: Text(l.questionBankTitle),
        actions: [
          IconButton(
            tooltip: l.questionBankWrongTitle,
            icon: const Icon(Icons.assignment_late_outlined),
            onPressed: () => context.push(Routes.wrongAnswers),
          ),
          IconButton(
            tooltip: l.examBookmark,
            icon: const Icon(Icons.bookmarks_outlined),
            onPressed: () => context.push(Routes.bookmarks),
          ),
        ],
      ),
      body: AsyncView<List<Subject>>(
        value: subjects,
        loading: const SkeletonList(itemCount: 8),
        onRetry: () => ref.invalidate(trackSubjectsProvider(track)),
        isEmpty: (list) => list.isEmpty,
        empty: EmptyView(title: l.questionBankEmpty, message: l.questionBankEmptyBody),
        data: (list) => RefreshIndicator(
          onRefresh: () => refreshSubjects(ref),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl),
            itemCount: list.length + 3,
            separatorBuilder: (_, i) => i <= 1 ? Gap.h16 : Gap.h8,
            itemBuilder: (context, i) {
              if (i == 0) return const TrackSelector();
              if (i == 1) return _Hero(track: track, total: list.fold(0, (sum, s) => sum + s.questionCount));
              if (i == 2) return Text(l.questionBankSubjects, style: Theme.of(context).textTheme.titleMedium);
              return SubjectCard(subject: list[i - 3], track: track);
            },
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.track, required this.total});
  final String track;
  final int total;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: Gap.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.library_books_rounded, color: scheme.onPrimaryContainer, size: 32),
                Gap.w12,
                Expanded(
                  child: Text(
                    l.questionBankHeroTitle(context.n(total)),
                    style: theme.textTheme.titleMedium?.copyWith(color: scheme.onPrimaryContainer),
                  ),
                ),
              ],
            ),
            Gap.h8,
            Text(l.questionBankHeroBody, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onPrimaryContainer)),
            Gap.h12,
            FilledButton.icon(
              onPressed: () => context.push(Routes.practice(track: track)),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(l.questionBankPracticeAll),
            ),
            Gap.h8,
            ActionChip(
              avatar: const Icon(Icons.assignment_late_outlined, size: 18),
              label: Text(l.questionBankWrongTitle),
              onPressed: () => context.push(Routes.wrongAnswers),
            ),
          ],
        ),
      ),
    );
  }
}

/// Subject row: icon, name, marks in the section's pattern + question
/// count, offline state, mastery ring and the offline download control.
class SubjectCard extends ConsumerWidget {
  const SubjectCard({required this.subject, this.track, super.key});

  final Subject subject;

  /// The section the list belongs to (null: BCS marks, every question).
  final String? track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final offline = ref.watch(offlinePacksProvider.select((s) => s.packs.containsKey(subject.id)));
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(Routes.subjectDetail(subject.id, track: track)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.xs, Gap.md),
          child: Row(
            children: [
              SubjectBadge(icon: subject.iconData, color: subject.color),
              Gap.w12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subject.name(context), style: theme.textTheme.titleSmall),
                    Gap.h4,
                    Text(
                      track == null
                          ? l.questionBankSubjectMeta(context.n(subject.bcsMarks), context.n(subject.questionCount))
                          : l.questionBankTrackSubjectMeta(
                              context.n(subject.trackMarks ?? 0),
                              context.n(subject.questionCount),
                            ),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    if (offline)
                      Padding(
                        padding: const EdgeInsets.only(top: Gap.xxs),
                        child: Row(
                          children: [
                            const Icon(Icons.offline_pin_rounded, size: 14, color: AppColors.success),
                            Gap.w4,
                            Text(
                              l.questionBankOfflineReady,
                              style: theme.textTheme.labelSmall?.copyWith(color: AppColors.success),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              MasteryRing(mastery: subject.mastery),
              OfflinePackButton(subject: subject),
            ],
          ),
        ),
      ),
    );
  }
}
