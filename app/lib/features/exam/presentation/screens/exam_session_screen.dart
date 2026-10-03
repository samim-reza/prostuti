import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/offline/offline_queue.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:prostuti/features/exam/application/exam_clock.dart';
import 'package:prostuti/features/exam/application/exam_failure_messages.dart';
import 'package:prostuti/features/exam/application/exam_providers.dart';
import 'package:prostuti/features/exam/application/exam_session_controller.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/exam/presentation/utils/exam_title.dart';
import 'package:prostuti/features/exam/presentation/widgets/exam_session_widgets.dart';

/// The exam hall: sticky timer + progress header, scrollable question list
/// with ক খ গ ঘ bubbles, flags, a question map, auto-submit at 0 and an
/// offline-safe submit (queued when there is no internet).
class ExamSessionScreen extends ConsumerStatefulWidget {
  const ExamSessionScreen({required this.sessionId, super.key});
  final String sessionId;

  @override
  ConsumerState<ExamSessionScreen> createState() => _ExamSessionScreenState();
}

class _ExamSessionScreenState extends ConsumerState<ExamSessionScreen> with WidgetsBindingObserver {
  final _scroll = ScrollController();
  List<GlobalKey> _keys = const [];
  ExamCountdown? _countdown;
  bool _navigated = false;
  bool _timeUpDialogOpen = false;

  AsyncNotifierProvider<ExamSessionController, ExamTakingState> get _provider =>
      examSessionControllerProvider(widget.sessionId);
  ExamSessionController get _controller => ref.read(_provider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    OfflineQueue.instance.pendingCount.addListener(_onQueueChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    OfflineQueue.instance.pendingCount.removeListener(_onQueueChanged);
    _countdown?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      unawaited(_controller.flush());
    } else if (state == AppLifecycleState.resumed) {
      _countdown?.tick();
    }
  }

  void _onSessionLoaded(ExamSession session, ExamTakingState state) {
    if (_countdown != null) return;
    _keys = List.generate(session.questions.length, (_) => GlobalKey());
    final countdown = ExamCountdown(
      deadline: session.deadlineAt,
      onPhaseChanged: _onPhaseChanged,
      onExpired: () => unawaited(_onTimeUp()),
    );
    _countdown = countdown;
    if (!state.isLocked) WidgetsBinding.instance.addPostFrameCallback((_) => countdown.start());
  }

  void _onPhaseChanged(TimerPhase phase) {
    if (!mounted) return;
    final l = context.l10n;
    switch (phase) {
      case TimerPhase.warning:
        showInfoSnack(context, l.examWarnFive);
      case TimerPhase.critical:
        showInfoSnack(context, l.examWarnOne);
      case TimerPhase.normal:
      case TimerPhase.expired:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------------

  Future<void> _confirmAndSubmit() async {
    final s = ref.read(_provider).value;
    if (s == null || s.isLocked) return;
    final ok = await showSubmitConfirmDialog(
      context,
      answered: s.sheet.answeredCount,
      total: s.total,
      flagged: s.sheet.flaggedCount,
      negativeMark: s.session.negativeMark,
    );
    if (ok && mounted) await _submit();
  }

  Future<void> _onTimeUp() async {
    final s = ref.read(_provider).value;
    if (!mounted || s == null || s.isLocked) return;
    _timeUpDialogOpen = true;
    final l = context.l10n;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            icon: const Icon(Icons.alarm_on_rounded, size: 36),
            title: Text(l.examTimeUpTitle, textAlign: TextAlign.center),
            content: Row(
              children: [
                const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
                Gap.w16,
                Expanded(child: Text(l.examTimeUpBody)),
              ],
            ),
          ),
        ),
      ),
    );
    await _submit();
  }

  void _closeTimeUpDialog() {
    if (_timeUpDialogOpen && mounted) {
      _timeUpDialogOpen = false;
      Navigator.of(context).pop();
    }
  }

  Future<void> _submit() async {
    final result = await _controller.submit();
    _closeTimeUpDialog();
    if (!mounted) return;
    if (result != null) {
      _goToResult(result);
      return;
    }
    final s = ref.read(_provider).value;
    if (s == null) return;
    if (s.isQueued) {
      _countdown?.stop();
      _refreshExamLists();
      return;
    }
    if (s.phase == SubmitPhase.failed) await _showSubmitFailed(s.error);
  }

  Future<void> _showSubmitFailed(AppFailure? error) async {
    final l = context.l10n;
    final message = (error == null || error is NetworkFailure)
        ? l.examSubmitFailedBody
        : '${examErrorMessage(context, error)}\n\n${l.examSubmitFailedBody}';
    final retry = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.cloud_off_rounded, color: Theme.of(ctx).colorScheme.error, size: 32),
        title: Text(l.examSubmitFailedTitle, textAlign: TextAlign.center),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.close)),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.examSubmitRetry),
          ),
        ],
      ),
    );
    if ((retry ?? false) && mounted) await _submit();
  }

  void _onQueueChanged() {
    final s = ref.read(_provider).value;
    if (s == null || !s.isQueued) return;
    final result = _controller.checkQueued();
    if (result != null && mounted) _goToResult(result);
  }

  void _refreshExamLists() {
    ref
      ..invalidate(activeExamProvider)
      ..invalidate(recentExamHistoryProvider)
      ..invalidate(examHistoryProvider);
  }

  void _goToResult(ExamResult result) {
    if (_navigated) return;
    _navigated = true;
    _countdown?.stop();
    _refreshExamLists();
    // Mastery changed → subjects overview must refetch.
    unawaited(ref.read(catalogRepositoryProvider).invalidateSubjects());
    ref.invalidate(subjectsProvider);
    final session = ref.read(_provider).value?.session;
    if (session?.kind == ExamKind.placement) {
      context.go(Routes.onboardingResult);
    } else {
      context.pushReplacement(Routes.examResult(widget.sessionId));
    }
  }

  // ---------------------------------------------------------------------------
  // Leaving & navigation
  // ---------------------------------------------------------------------------

  Future<void> _onPopRequested() async {
    final l = context.l10n;
    final leave = await confirmDialog(
      context,
      title: l.examLeaveTitle,
      message: l.examLeaveBody,
      confirmLabel: l.examLeaveConfirm,
    );
    if (!leave || !mounted) return;
    await _controller.flush();
    if (!mounted) return;
    _leave();
  }

  void _leave() {
    ref.invalidate(activeExamProvider);
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.exams);
    }
  }

  Future<void> _openNavigator(List<int> questionIds) async {
    final index = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => QuestionNavigatorSheet(sessionId: widget.sessionId, questionIds: questionIds),
    );
    if (index != null && mounted) _jumpTo(index);
  }

  /// Scrolls to question [index]; off-screen items are approached by an
  /// estimated offset first, then aligned precisely once built.
  void _jumpTo(int index, {int attempt = 0}) {
    if (index < 0 || index >= _keys.length || !_scroll.hasClients) return;
    final ctx = _keys[index].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.02,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
      return;
    }
    if (attempt > 3) return;
    final pos = _scroll.position;
    final perItem = (pos.maxScrollExtent + pos.viewportDimension) / _keys.length;
    _scroll.jumpTo((perItem * index).clamp(0, pos.maxScrollExtent));
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(index, attempt: attempt + 1));
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    registerExamFailureMessages();
    final session = ref.watch(_provider.select((a) => a.whenData((s) => s.session)));
    final phase = ref.watch(_provider.select((a) => a.value?.phase));

    ref.listen(_provider, (prev, next) {
      final s = next.value;
      if (s != null) _onSessionLoaded(s.session, s);
    });
    final current = ref.read(_provider).value;
    if (current != null && _countdown == null) _onSessionLoaded(current.session, current);

    final blocking = session.hasValue && phase != SubmitPhase.queued && phase != SubmitPhase.done;
    return PopScope(
      canPop: !blocking,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_onPopRequested());
      },
      child: session.when(
        loading: () => Scaffold(appBar: AppBar(), body: const SkeletonCards(height: 220)),
        error: (e, _) => _LoadError(
          error: e,
          sessionId: widget.sessionId,
          onRetry: () => ref.invalidate(_provider),
          onResult: _goToResult,
        ),
        data: (s) => phase == SubmitPhase.queued ? _QueuedView(session: s) : _buildExam(context, s),
      ),
    );
  }

  Widget _buildExam(BuildContext context, ExamSession session) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final countdown = _countdown;
    final submitting = ref.watch(_provider.select((a) => a.value?.isSubmitting ?? false));
    final ids = [for (final q in session.questions) q.id];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: l.examLeaveTitle,
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          examTitleOf(context, ref, session.title, session.kind),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        actions: [
          IconButton(
            tooltip: l.examNavigator,
            icon: const Icon(Icons.grid_view_rounded),
            onPressed: () => unawaited(_openNavigator(ids)),
          ),
          Gap.w4,
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: _ProgressHeader(
            sessionId: widget.sessionId,
            total: session.total,
            timer: countdown == null ? null : ExamTimerChip(remaining: countdown.remaining),
          ),
        ),
      ),
      body: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, Gap.xxl),
        itemCount: session.questions.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) return _ToggleHint(negativeMark: session.negativeMark);
          final index = i - 1;
          return Padding(
            key: index < _keys.length ? _keys[index] : null,
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: ExamQuestionCard(sessionId: widget.sessionId, question: session.questions[index], number: index + 1),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.sm),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6))),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => unawaited(_openNavigator(ids)),
                  icon: const Icon(Icons.grid_view_rounded),
                  label: Text(l.examNavigator, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              Gap.w12,
              Expanded(
                child: FilledButton.icon(
                  onPressed: submitting ? null : () => unawaited(_confirmAndSubmit()),
                  icon: submitting
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_rounded),
                  label: Text(submitting ? l.examSubmitting : l.examSubmit, maxLines: 1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Timer + answered count + progress bar (rebuilds on answer count only).
class _ProgressHeader extends ConsumerWidget {
  const _ProgressHeader({required this.sessionId, required this.total, required this.timer});

  final String sessionId;
  final int total;
  final Widget? timer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final provider = examSessionControllerProvider(sessionId);
    final answered = ref.watch(provider.select((a) => a.value?.sheet.answeredCount ?? 0));
    final flagged = ref.watch(provider.select((a) => a.value?.sheet.flaggedCount ?? 0));
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
          child: Row(
            children: [
              ?timer,
              const Spacer(),
              if (flagged > 0) ...[
                Icon(Icons.flag_rounded, size: 16, color: scheme.tertiary),
                Gap.w4,
                Text(context.n(flagged), style: Theme.of(context).textTheme.labelLarge),
                Gap.w12,
              ],
              Text(
                l.examAnsweredOf(context.n(answered), context.n(total)),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
        ),
        Gap.h8,
        TweenAnimationBuilder<double>(
          tween: Tween(end: total == 0 ? 0 : answered / total),
          duration: const Duration(milliseconds: 250),
          builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 4),
        ),
      ],
    );
  }
}

class _ToggleHint extends StatelessWidget {
  const _ToggleHint({required this.negativeMark});
  final double negativeMark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: scheme.onSurfaceVariant),
          Gap.w8,
          Expanded(
            child: Text(
              context.l10n.examToggleHint(Fmt.score(negativeMark, bangla: context.isBn)),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// Offline submit: the answers wait in the outbox and go out automatically.
class _QueuedView extends ConsumerWidget {
  const _QueuedView({required this.session});
  final ExamSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(examTitleOf(context, ref, session.title, session.kind), maxLines: 1)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Gap.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(Gap.xl),
                decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(Icons.cloud_upload_rounded, size: 52, color: scheme.primary),
              ),
              Gap.h24,
              Text(l.examSubmitQueuedTitle, style: Theme.of(context).textTheme.headlineSmall),
              Gap.h12,
              Text(l.examSubmitQueuedBody, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
              Gap.h8,
              Text(
                l.examSubmitQueuedHint,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              Gap.h24,
              const LinearProgressIndicator(),
              Gap.h24,
              FilledButton.tonalIcon(
                onPressed: () => context.go(Routes.exams),
                icon: const Icon(Icons.quiz_rounded),
                label: Text(l.examBackToExams),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The session couldn't be opened (finished elsewhere, deadline passed,
/// offline without a cached copy…).
class _LoadError extends ConsumerStatefulWidget {
  const _LoadError({required this.error, required this.sessionId, required this.onRetry, required this.onResult});

  final Object error;
  final String sessionId;
  final VoidCallback onRetry;
  final ValueChanged<ExamResult> onResult;

  @override
  ConsumerState<_LoadError> createState() => _LoadErrorState();
}

class _LoadErrorState extends ConsumerState<_LoadError> {
  bool _busy = false;

  Future<void> _recover() async {
    if (!ConnectivityService.instance.isOnline) {
      showInfoSnack(context, context.l10n.offlineUnavailable);
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await ref.read(examSessionControllerProvider(widget.sessionId).notifier).recover();
      if (mounted) widget.onResult(result);
    } on Object catch (e) {
      if (mounted) showExamError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final failure = AppFailure.from(widget.error);
    final missing = failure is NotFoundFailure;
    return Scaffold(
      appBar: AppBar(),
      body: missing
          ? EmptyView(
              icon: Icons.event_busy_rounded,
              title: l.examSessionMissingTitle,
              message: l.examSessionMissingBody,
              action: _busy ? null : () => unawaited(_recover()),
              actionLabel: l.examSeeResult,
            )
          : ErrorView(error: failure, onRetry: widget.onRetry),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: TextButton(onPressed: () => context.go(Routes.exams), child: Text(l.examBackToExams)),
        ),
      ),
    );
  }
}
