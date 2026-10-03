import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:prostuti/features/exam/application/exam_failure_messages.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/exam/presentation/widgets/exam_launcher.dart';
import 'package:prostuti/features/question_bank/presentation/screens/question_bank_screen.dart';
import 'package:prostuti/features/question_bank/presentation/widgets/offline_pack_widgets.dart';
import 'package:prostuti/features/question_bank/presentation/widgets/subject_widgets.dart';

/// One subject: mastery, practice / exam actions, offline pack and its
/// topics with mastery bars (each with topic practice and topic exam).
class SubjectDetailScreen extends ConsumerWidget {
  const SubjectDetailScreen({required this.subjectId, super.key});
  final int subjectId;

  Future<void> _subjectExam(BuildContext context, WidgetRef ref, Subject subject) async {
    final choice = await showExamSetupSheet(context, title: context.l10n.questionBankSubjectExam);
    if (choice == null || !context.mounted) return;
    await ExamLauncher.start(context, ref, ExamKind.subject, config: {'subject_id': subject.id, 'count': choice.count});
  }

  Future<void> _topicExam(BuildContext context, WidgetRef ref, Topic topic) async {
    final choice = await showExamSetupSheet(context, title: context.l10n.questionBankTopicExam, initialCount: 10);
    if (choice == null || !context.mounted) return;
    await ExamLauncher.start(context, ref, ExamKind.topic, config: {'topic_id': topic.id, 'count': choice.count});
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    registerExamFailureMessages();
    final l = context.l10n;
    final subjects = ref.watch(subjectsProvider);
    final subject = ref.watch(subjectByIdProvider(subjectId));

    if (subject == null) {
      return Scaffold(
        appBar: AppBar(),
        body: subjects.isLoading
            ? const SkeletonList()
            : subjects.hasError
            ? ErrorView(error: subjects.error!, onRetry: () => ref.invalidate(subjectsProvider))
            : EmptyView(icon: Icons.search_off_rounded, title: l.questionBankSubjectNotFound),
      );
    }

    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(subject.name(context))),
      body: RefreshIndicator(
        onRefresh: () => QuestionBankScreen.refreshSubjects(ref),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl),
          children: [
            Card(
              child: Padding(
                padding: Gap.card,
                child: Column(
                  children: [
                    Row(
                      children: [
                        SubjectBadge(icon: subject.iconData, color: subject.color, size: 56),
                        Gap.w16,
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(subject.name(context), style: theme.textTheme.titleMedium),
                              Gap.h4,
                              Text(
                                l.questionBankSubjectMeta(
                                  context.n(subject.bcsMarks),
                                  context.n(subject.questionCount),
                                ),
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        MasteryRing(mastery: subject.mastery, size: 60),
                      ],
                    ),
                    Gap.h16,
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => context.push(Routes.practice(subjectId: subject.id)),
                            icon: const Icon(Icons.edit_note_rounded),
                            label: Text(l.questionBankPractice, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                        Gap.w12,
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => unawaited(_subjectExam(context, ref, subject)),
                            icon: const Icon(Icons.timer_outlined),
                            label: Text(l.questionBankSubjectExam, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Gap.h12,
            OfflinePackCard(subject: subject),
            Gap.h16,
            Text(l.questionBankTopics, style: theme.textTheme.titleMedium),
            Gap.h8,
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < subject.topics.length; i++) ...[
                    if (i > 0) const Divider(indent: Gap.lg, endIndent: Gap.lg),
                    _TopicRow(
                      topic: subject.topics[i],
                      onPractice: () => context.push(Routes.practice(topicId: subject.topics[i].id)),
                      onExam: () => unawaited(_topicExam(context, ref, subject.topics[i])),
                    ),
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

class _TopicRow extends StatelessWidget {
  const _TopicRow({required this.topic, required this.onPractice, required this.onExam});

  final Topic topic;
  final VoidCallback onPractice;
  final VoidCallback onExam;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return InkWell(
      onTap: onPractice,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.xs, Gap.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(topic.name(context), style: Theme.of(context).textTheme.bodyLarge),
                  Gap.h4,
                  MasteryBar(mastery: topic.mastery),
                ],
              ),
            ),
            Gap.w4,
            IconButton(
              tooltip: l.questionBankTopicPractice,
              icon: const Icon(Icons.edit_note_rounded),
              onPressed: onPractice,
            ),
            IconButton(tooltip: l.questionBankTopicExam, icon: const Icon(Icons.timer_outlined), onPressed: onExam),
          ],
        ),
      ),
    );
  }
}
