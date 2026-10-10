import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:prostuti/features/exam/application/exam_failure_messages.dart';
import 'package:prostuti/features/exam/application/question_bookmarks.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/question_bank/application/practice_controller.dart';
import 'package:prostuti/features/question_bank/application/question_bank_providers.dart';
import 'package:prostuti/features/question_bank/presentation/widgets/practice_question_card.dart';

/// One question at a time from a subject, topic or source. Online it pages
/// through `get_practice_questions` (prefetching when 3 remain); with a
/// downloaded pack it starts instantly and works offline.
class PracticeScreen extends ConsumerStatefulWidget {
  const PracticeScreen({this.subjectId, this.topicId, this.sourceId, this.track, super.key});
  final int? subjectId;
  final int? topicId;
  final int? sourceId;
  final String? track;

  @override
  ConsumerState<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends ConsumerState<PracticeScreen> {
  late final _query = PracticeQuery(
    subjectId: widget.subjectId,
    topicId: widget.topicId,
    sourceId: widget.sourceId,
    track: widget.track,
  );
  final _pages = PageController();
  ProviderContainer? _container;
  bool _answeredAny = false;

  NotifierProvider<PracticeController, PracticeState> get _provider => practiceControllerProvider(_query);
  PracticeController get _controller => ref.read(_provider.notifier);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container ??= ProviderScope.containerOf(context, listen: false);
  }

  @override
  void dispose() {
    _pages.dispose();
    final container = _container;
    if (_answeredAny && container != null) {
      // Mastery changed: refresh the subjects overview once we're gone.
      unawaited(
        Future.microtask(() async {
          await container.read(catalogRepositoryProvider).invalidateSubjects();
          container
            ..invalidate(subjectsProvider)
            ..invalidate(trackSubjectsProvider);
        }),
      );
    }
    super.dispose();
  }

  String _title(BuildContext context) {
    final l = context.l10n;
    final subjects = ref.watch(subjectsProvider).value ?? const <Subject>[];
    if (widget.topicId != null) {
      for (final s in subjects) {
        for (final t in s.topics) {
          if (t.id == widget.topicId) return t.name(context);
        }
      }
    }
    if (widget.subjectId != null) {
      for (final s in subjects) {
        if (s.id == widget.subjectId) return s.name(context);
      }
    }
    if (widget.sourceId != null) {
      final source = ref.watch(sourceByIdProvider(widget.sourceId!));
      if (source != null) return source.name;
    }
    return l.questionBankPracticeTitle;
  }

  Future<void> _answer(Question q, int index) async {
    try {
      await _controller.answer(q, index);
      _answeredAny = true;
    } on Object catch (e) {
      if (mounted) showExamError(context, e);
    }
  }

  Future<void> _reveal(Question q) async {
    try {
      await _controller.reveal(q);
    } on Object catch (e) {
      if (mounted) showExamError(context, e);
    }
  }

  void _goTo(int page) {
    if (!_pages.hasClients) return;
    _pages.animateToPage(page, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    registerExamFailureMessages();
    final l = context.l10n;
    final state = ref.watch(_provider);

    // Keep the page view in sync with programmatic index changes, and load
    // bookmark status for every new batch.
    ref
      ..listen(_provider.select((s) => s.index), (prev, next) {
        if (_pages.hasClients && (_pages.page?.round() ?? 0) != next) _goTo(next);
      })
      ..listen(_provider.select((s) => s.items.length), (prev, next) {
        final current = ref.read(_provider);
        unawaited(ref.read(questionBookmarksProvider.notifier).ensureLoaded(current.items.map((q) => q.id)));
        if ((prev ?? 0) == 0 && next > 0) {
          // A fresh list (filter switched / restart): start from its first page.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_pages.hasClients) _pages.jumpToPage(current.index);
          });
        }
      });

    return Scaffold(
      appBar: AppBar(
        title: Text(_title(context), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (state.attempted > 0)
            Padding(
              padding: const EdgeInsets.only(right: Gap.md),
              child: Center(
                child: Tooltip(
                  message: l.questionBankScoreHint,
                  child: Chip(
                    avatar: const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success),
                    label: Text(l.questionBankScore(context.n(state.correct), context.n(state.attempted))),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          _Toolbar(state: state, onUnseen: (v) => unawaited(_controller.setUnseenOnly(v))),
          Expanded(child: _body(context, state)),
        ],
      ),
      bottomNavigationBar: state.items.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xs, Gap.lg, Gap.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: state.index > 0 ? _controller.previous : null,
                        icon: const Icon(Icons.chevron_left_rounded),
                        label: Text(l.questionBankPrevious, maxLines: 1),
                      ),
                    ),
                    Gap.w12,
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: state.index < state.items.length ? _controller.next : null,
                        icon: const Icon(Icons.chevron_right_rounded),
                        iconAlignment: IconAlignment.end,
                        label: Text(l.questionBankNext, maxLines: 1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _body(BuildContext context, PracticeState state) {
    final l = context.l10n;
    if (state.isLoadingFirst && state.items.isEmpty) return const SkeletonCards(count: 1, height: 420);
    if (state.needsPack && state.items.isEmpty) {
      return EmptyView(
        icon: Icons.cloud_off_rounded,
        title: l.questionBankOfflineNeedPack,
        message: l.questionBankOfflineNeedPackBody,
        action: () => context.push(Routes.questionBank),
        actionLabel: l.questionBankTitle,
      );
    }
    if (state.error != null && state.items.isEmpty) {
      return ErrorView(error: state.error!, onRetry: () => unawaited(_controller.retry()));
    }
    if (state.items.isEmpty) {
      return state.unseenOnly
          ? EmptyView(
              icon: Icons.done_all_rounded,
              title: l.questionBankEmptyUnseen,
              message: l.questionBankEmptyUnseenBody,
              action: () => unawaited(_controller.setUnseenOnly(false)),
              actionLabel: l.questionBankShowAll,
            )
          : EmptyView(title: l.questionBankEmpty, message: l.questionBankEmptyBody);
    }
    return PageView.builder(
      controller: _pages,
      itemCount: state.items.length + 1,
      onPageChanged: _controller.goTo,
      itemBuilder: (context, i) {
        if (i >= state.items.length) return _EndPage(state: state, controller: _controller);
        final q = state.items[i];
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.xl),
          child: _PracticeItem(provider: _provider, question: q, number: i + 1, onAnswer: _answer, onReveal: _reveal),
        );
      },
    );
  }
}

/// Rebuilds only when this question's outcome changes.
class _PracticeItem extends ConsumerWidget {
  const _PracticeItem({
    required this.provider,
    required this.question,
    required this.number,
    required this.onAnswer,
    required this.onReveal,
  });

  final NotifierProvider<PracticeController, PracticeState> provider;
  final Question question;
  final int number;
  final Future<void> Function(Question q, int index) onAnswer;
  final Future<void> Function(Question q) onReveal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outcome = ref.watch(provider.select((s) => s.outcomes[question.id]));
    return PracticeQuestionCard(
      question: question,
      number: number,
      outcome: outcome,
      onSelect: (i) => unawaited(onAnswer(question, i)),
      onReveal: () => unawaited(onReveal(question)),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.state, required this.onUnseen});

  final PracticeState state;
  final ValueChanged<bool> onUnseen;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final total = state.items.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xs, Gap.lg, Gap.xs),
      child: Row(
        children: [
          FilterChip(
            label: Text(l.questionBankUnseenOnly),
            selected: state.unseenOnly,
            onSelected: state.isLoadingFirst ? null : onUnseen,
          ),
          if (state.fromPack) ...[
            Gap.w8,
            Tooltip(
              message: l.questionBankOfflineModeHint,
              child: Chip(
                avatar: const Icon(Icons.offline_pin_rounded, size: 16, color: AppColors.success),
                label: Text(l.questionBankOfflineMode),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
          const Spacer(),
          if (total > 0 && state.index < total)
            Text(
              '${context.n(state.index + 1)}${state.hasMore ? '' : '/${context.n(total)}'}',
              style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class _EndPage extends StatelessWidget {
  const _EndPage({required this.state, required this.controller});

  final PracticeState state;
  final PracticeController controller;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (state.hasMore) {
      if (state.error != null) {
        final offline = state.error is NetworkFailure;
        return ErrorView(error: state.error!, onRetry: () => unawaited(controller.retry()), compact: offline);
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [const CircularProgressIndicator(), Gap.h12, Text(l.questionBankLoadingMore)],
        ),
      );
    }
    return EmptyView(
      icon: Icons.emoji_events_rounded,
      title: l.questionBankEndTitle,
      message: [
        l.questionBankEndBody,
        if (state.attempted > 0) l.questionBankEndScore(context.n(state.correct), context.n(state.attempted)),
      ].join('\n\n'),
      action: () => unawaited(controller.restart()),
      actionLabel: l.questionBankStartOver,
    );
  }
}
