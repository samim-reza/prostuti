import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/paged_list_view.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:prostuti/features/exam/application/exam_failure_messages.dart';
import 'package:prostuti/features/exam/application/question_bookmarks.dart';
import 'package:prostuti/features/exam/presentation/widgets/review_question_card.dart';
import 'package:prostuti/features/question_bank/application/question_bank_providers.dart';
import 'package:prostuti/features/question_bank/data/question_bank_models.dart';

/// "ভুলের খাতা": questions whose latest graded attempt was wrong, with the
/// user's answer vs the correct one, explanation and "practise again".
class WrongAnswersScreen extends ConsumerStatefulWidget {
  const WrongAnswersScreen({super.key});

  @override
  ConsumerState<WrongAnswersScreen> createState() => _WrongAnswersScreenState();
}

class _WrongAnswersScreenState extends ConsumerState<WrongAnswersScreen> {
  int? _subjectId;

  @override
  Widget build(BuildContext context) {
    registerExamFailureMessages();
    final l = context.l10n;
    final provider = wrongAnswersProvider(_subjectId);
    final state = ref.watch(provider);
    final notifier = ref.read(provider.notifier);
    final subjects = ref.watch(subjectsProvider).value ?? const <Subject>[];

    ref.listen(provider.select((s) => s.items.length), (_, _) {
      final ids = ref.read(provider).items.map((w) => w.question.id);
      unawaited(ref.read(questionBookmarksProvider.notifier).ensureLoaded(ids));
    });

    return Scaffold(
      appBar: AppBar(title: Text(l.questionBankWrongTitle)),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.sm),
              children: [
                ChoiceChip(
                  label: Text(l.questionBankWrongAll),
                  selected: _subjectId == null,
                  onSelected: (_) => setState(() => _subjectId = null),
                ),
                for (final s in subjects) ...[
                  Gap.w8,
                  ChoiceChip(
                    avatar: Icon(s.iconData, size: 16, color: s.color),
                    label: Text(s.name(context)),
                    selected: _subjectId == s.id,
                    onSelected: (_) => setState(() => _subjectId = s.id),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: PagedListView<WrongAnswer>(
              key: ValueKey(_subjectId),
              state: state,
              onLoadMore: notifier.loadMore,
              onRefresh: notifier.refresh,
              onRetry: notifier.retry,
              loading: const SkeletonCards(height: 300),
              padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.xxl),
              separator: Gap.h12,
              empty: EmptyView(
                icon: Icons.celebration_rounded,
                title: l.questionBankWrongEmpty,
                message: l.questionBankWrongEmptyBody,
              ),
              itemBuilder: (context, item, _) => ReviewQuestionCard(
                key: ValueKey(item.question.id),
                question: item.question,
                subtitle: Fmt.timeAgo(item.attemptedAt, bangla: context.isBn),
                footer: TextButton.icon(
                  onPressed: () => context.push(Routes.practice(subjectId: item.question.subjectId)),
                  icon: const Icon(Icons.replay_rounded, size: 18),
                  label: Text(l.questionBankPracticeAgain),
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
