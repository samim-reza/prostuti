import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/rate_limit/debouncer.dart';
import 'package:prostuti/features/exam/application/exam_answers.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/exam/data/exam_repository.dart';

/// Submit lifecycle. `queued` = offline; the outbox submits it later.
enum SubmitPhase { idle, submitting, failed, queued, done }

@immutable
class ExamTakingState {
  const ExamTakingState({
    required this.session,
    this.sheet = const ExamAnswerSheet(),
    this.phase = SubmitPhase.idle,
    this.error,
    this.result,
  });

  final ExamSession session;
  final ExamAnswerSheet sheet;
  final SubmitPhase phase;
  final AppFailure? error;
  final ExamResult? result;

  int get total => session.total;
  bool get isSubmitting => phase == SubmitPhase.submitting;
  bool get isDone => phase == SubmitPhase.done;
  bool get isQueued => phase == SubmitPhase.queued;
  bool get isLocked => isSubmitting || isDone || isQueued;

  ExamTakingState copyWith({
    ExamAnswerSheet? sheet,
    SubmitPhase? phase,
    AppFailure? error,
    bool clearError = false,
    ExamResult? result,
  }) => ExamTakingState(
    session: session,
    sheet: sheet ?? this.sheet,
    phase: phase ?? this.phase,
    error: clearError ? null : (error ?? this.error),
    result: result ?? this.result,
  );
}

/// State of one exam being taken: answers (persisted on device, debounced
/// 300 ms), flags and the submit lifecycle (double-submit safe, retryable).
class ExamSessionController extends AsyncNotifier<ExamTakingState> {
  ExamSessionController(this.sessionId);

  final String sessionId;
  final _saveDebouncer = Debouncer(const Duration(milliseconds: 300));
  ExamAnswerSheet? _unsaved;
  late ExamRepository _repo;

  @override
  Future<ExamTakingState> build() async {
    _repo = ref.watch(examRepositoryProvider);
    ref.onDispose(() {
      _saveDebouncer.dispose();
      final pending = _unsaved;
      if (pending != null) unawaited(_persist(pending));
    });
    final session = await _repo.loadSession(sessionId);
    final saved = ExamAnswerSheet(answers: _repo.savedAnswers(sessionId), flagged: _repo.savedFlags(sessionId));
    final sheet = saved.retainValid({for (final q in session.questions) q.id: q.options.length});
    // Re-opened while its submission still waits for connectivity.
    final queued = _repo.isSubmissionPending(sessionId);
    return ExamTakingState(session: session, sheet: sheet, phase: queued ? SubmitPhase.queued : SubmitPhase.idle);
  }

  ExamTakingState? get _current => state.value;

  void select(int questionId, int optionIndex) {
    final s = _current;
    if (s == null || s.isLocked) return;
    _apply(s.copyWith(sheet: s.sheet.select(questionId, optionIndex)));
  }

  void toggleFlag(int questionId) {
    final s = _current;
    if (s == null || s.isLocked) return;
    _apply(s.copyWith(sheet: s.sheet.toggleFlag(questionId)));
  }

  void _apply(ExamTakingState next) {
    state = AsyncData(next);
    _unsaved = next.sheet;
    _saveDebouncer(() => unawaited(_persist(next.sheet)));
  }

  Future<void> _persist(ExamAnswerSheet sheet) async {
    if (identical(_unsaved, sheet)) _unsaved = null;
    try {
      await Future.wait([_repo.saveAnswers(sessionId, sheet.answers), _repo.saveFlags(sessionId, sheet.flagged)]);
    } on Object catch (e) {
      debugPrint('exam: could not persist answers: $e');
    }
  }

  /// Writes pending answers immediately (app paused, before submit).
  Future<void> flush() async {
    final pending = _unsaved;
    if (pending == null) return;
    _saveDebouncer.dispose(); // cancels the scheduled write
    await _persist(pending);
  }

  /// Submits once; concurrent calls are ignored and a finished exam returns
  /// its result. Offline, the submission is queued (phase `queued`) and the
  /// outbox delivers it later. On failure the answers stay safe on device.
  Future<ExamResult?> submit() async {
    final s = _current;
    if (s == null || s.isSubmitting) return null;
    if (s.isDone) return s.result;
    state = AsyncData(s.copyWith(phase: SubmitPhase.submitting, clearError: true));
    await flush();
    try {
      final outcome = await _repo.submitOrQueue(s.session, s.sheet.answers);
      if (!ref.mounted) return outcome.result;
      state = AsyncData(
        outcome.isQueued
            ? s.copyWith(phase: SubmitPhase.queued, clearError: true)
            : s.copyWith(phase: SubmitPhase.done, result: outcome.result, clearError: true),
      );
      return outcome.result;
    } on Object catch (e) {
      if (ref.mounted) state = AsyncData(s.copyWith(phase: SubmitPhase.failed, error: AppFailure.from(e)));
      return null;
    }
  }

  /// Called when the outbox drained: picks up the result stored by the
  /// queued submission. Returns it once available.
  ExamResult? checkQueued() {
    final s = _current;
    if (s == null || !s.isQueued || _repo.isSubmissionPending(sessionId)) return null;
    final result = _repo.cachedResult(sessionId);
    if (result != null) state = AsyncData(s.copyWith(phase: SubmitPhase.done, result: result));
    return result;
  }

  /// When the session can't be opened any more (deadline passed, opened on
  /// another device…): submit whatever was saved locally. The server returns
  /// the stored result for already-submitted sessions.
  Future<ExamResult> recover() => _repo.submit(sessionId, _repo.savedAnswers(sessionId));
}

final examSessionControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ExamSessionController, ExamTakingState, String>(ExamSessionController.new);
