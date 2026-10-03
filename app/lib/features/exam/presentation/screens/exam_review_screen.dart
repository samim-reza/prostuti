import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/exam/application/exam_failure_messages.dart';
import 'package:prostuti/features/exam/application/exam_providers.dart';
import 'package:prostuti/features/exam/application/question_bookmarks.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/exam/presentation/widgets/review_question_card.dart';

enum ReviewFilter { all, wrong, skipped, correct }

extension on ReviewFilter {
  bool accepts(Question q) => switch (this) {
    ReviewFilter.all => true,
    ReviewFilter.wrong => q.isCorrect == false,
    ReviewFilter.skipped => q.selectedIndex == null,
    ReviewFilter.correct => q.isCorrect ?? false,
  };

  String label(AppLocalizations l) => switch (this) {
    ReviewFilter.all => l.examReviewFilterAll,
    ReviewFilter.wrong => l.examReviewFilterWrong,
    ReviewFilter.skipped => l.examReviewFilterSkipped,
    ReviewFilter.correct => l.examReviewFilterCorrect,
  };
}

/// Answer review after submission: filter chips (all / wrong / skipped /
/// correct), green correct + red wrong highlighting, explanations, sources,
/// AI explanation, bookmark and report. Cached for offline reading.
class ExamReviewScreen extends ConsumerStatefulWidget {
  const ExamReviewScreen({required this.sessionId, super.key});
  final String sessionId;

  @override
  ConsumerState<ExamReviewScreen> createState() => _ExamReviewScreenState();
}

class _ExamReviewScreenState extends ConsumerState<ExamReviewScreen> {
  ReviewFilter _filter = ReviewFilter.all;
  bool _bookmarksRequested = false;

  void _loadBookmarks(List<Question> questions) {
    if (_bookmarksRequested || questions.isEmpty) return;
    _bookmarksRequested = true;
    unawaited(ref.read(questionBookmarksProvider.notifier).ensureLoaded(questions.map((q) => q.id), refresh: true));
  }

  @override
  Widget build(BuildContext context) {
    registerExamFailureMessages();
    final l = context.l10n;
    final value = ref.watch(examReviewProvider(widget.sessionId));
    ref.listen(examReviewProvider(widget.sessionId), (_, next) {
      final data = next.value;
      if (data != null) _loadBookmarks(data);
    });
    final loaded = value.value;
    if (loaded != null) _loadBookmarks(loaded);

    return Scaffold(
      appBar: AppBar(title: Text(l.examReviewTitle)),
      body: AsyncView<List<Question>>(
        value: value,
        loading: const SkeletonCards(height: 260),
        onRetry: () => ref.invalidate(examReviewProvider(widget.sessionId)),
        isEmpty: (list) => list.isEmpty,
        empty: EmptyView(icon: Icons.hourglass_empty_rounded, title: l.examReviewNotReady),
        data: (questions) {
          final counts = {for (final f in ReviewFilter.values) f: questions.where(f.accepts).length};
          // Keep each question's original number when filtering.
          final visible = [
            for (var i = 0; i < questions.length; i++)
              if (_filter.accepts(questions[i])) (i + 1, questions[i]),
          ];
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 56,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.sm),
                    children: [
                      for (final f in ReviewFilter.values) ...[
                        ChoiceChip(
                          label: Text(l.examReviewChip(f.label(l), context.n(counts[f] ?? 0))),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                        Gap.w8,
                      ],
                    ],
                  ),
                ),
              ),
              if (visible.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyView(icon: Icons.filter_alt_off_rounded, title: l.examReviewEmpty, compact: true),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.xxl),
                  sliver: SliverList.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => Gap.h12,
                    itemBuilder: (context, i) {
                      final (number, q) = visible[i];
                      return ReviewQuestionCard(key: ValueKey(q.id), question: q, number: number);
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
