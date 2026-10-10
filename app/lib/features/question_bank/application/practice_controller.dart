import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/features/exam/application/exam_failure_messages.dart';
import 'package:prostuti/features/exam/application/question_bookmarks.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/question_bank/application/offline_packs.dart';
import 'package:prostuti/features/question_bank/data/offline_pack_store.dart';
import 'package:prostuti/features/question_bank/data/question_bank_repository.dart';

/// What to practise: a subject, a topic and/or a source (all optional).
@immutable
class PracticeQuery {
  const PracticeQuery({this.subjectId, this.topicId, this.sourceId, this.track});

  final int? subjectId;
  final int? topicId;
  final int? sourceId;

  /// Exam section (bcs/bank/govt) from the question bank; null = all.
  final String? track;

  @override
  bool operator ==(Object other) =>
      other is PracticeQuery &&
      other.subjectId == subjectId &&
      other.topicId == topicId &&
      other.sourceId == sourceId &&
      other.track == track;

  @override
  int get hashCode => Object.hash(subjectId, topicId, sourceId, track);
}

/// The user's interaction with one practice question.
@immutable
class PracticeOutcome {
  const PracticeOutcome({
    this.selected,
    this.correctIndex,
    this.explanation,
    this.revealed = false,
    this.locked = false,
    this.pending = false,
  });

  final int? selected;
  final int? correctIndex;
  final String? explanation;

  /// Answer shown via "show answer" (no attempt graded).
  final bool revealed;

  /// Part of today's live daily exam — answers are hidden until submitted.
  final bool locked;

  /// Waiting for the server verdict.
  final bool pending;

  bool get isResolved => correctIndex != null;
  bool? get isCorrect => (selected == null || correctIndex == null || revealed) ? null : selected == correctIndex;
}

@immutable
class PracticeState {
  const PracticeState({
    this.items = const [],
    this.index = 0,
    this.hasMore = true,
    this.isLoadingFirst = true,
    this.isLoadingMore = false,
    this.error,
    this.unseenOnly = false,
    this.outcomes = const {},
    this.fromPack = false,
    this.needsPack = false,
  });

  final List<Question> items;
  final int index;
  final bool hasMore;
  final bool isLoadingFirst;
  final bool isLoadingMore;
  final AppFailure? error;
  final bool unseenOnly;
  final Map<int, PracticeOutcome> outcomes;

  /// Served from a downloaded offline pack (graded on device, synced later).
  final bool fromPack;

  /// Offline and nothing downloaded for this selection.
  final bool needsPack;

  Question? get current => index < items.length ? items[index] : null;
  bool get isEmpty => !isLoadingFirst && items.isEmpty && error == null && !hasMore;

  /// Graded answers this session (reveals don't count).
  int get attempted => outcomes.values.where((o) => o.isCorrect != null).length;
  int get correct => outcomes.values.where((o) => o.isCorrect ?? false).length;

  PracticeState copyWith({
    List<Question>? items,
    int? index,
    bool? hasMore,
    bool? isLoadingFirst,
    bool? isLoadingMore,
    AppFailure? error,
    bool clearError = false,
    bool? unseenOnly,
    Map<int, PracticeOutcome>? outcomes,
    bool? fromPack,
    bool? needsPack,
  }) => PracticeState(
    items: items ?? this.items,
    index: index ?? this.index,
    hasMore: hasMore ?? this.hasMore,
    isLoadingFirst: isLoadingFirst ?? this.isLoadingFirst,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    error: clearError ? null : (error ?? this.error),
    unseenOnly: unseenOnly ?? this.unseenOnly,
    outcomes: outcomes ?? this.outcomes,
    fromPack: fromPack ?? this.fromPack,
    needsPack: needsPack ?? this.needsPack,
  );
}

/// Prefetch rule: load the next batch when only [threshold] questions are
/// left after the one on screen, so "next" never waits on the network.
abstract final class PracticePrefetch {
  static const threshold = 3;

  static bool shouldPrefetch({
    required int index,
    required int loaded,
    required bool hasMore,
    required bool busy,
    int threshold = PracticePrefetch.threshold,
  }) => hasMore && !busy && (loaded - index - 1) <= threshold;
}

/// One-question-at-a-time practice.
///
/// * **Pack mode** — when a downloaded offline pack covers the selection
///   (always used when present: instant start, works offline): answers are
///   graded on device and buffered for `sync_practice_attempts`, handed to
///   the offline queue [PracticeSync.batchSize] at a time and when leaving.
/// * **Online mode** — `get_practice_questions` (keyset `p_after_id`) with
///   server-graded answers and prefetching.
class PracticeController extends Notifier<PracticeState> {
  PracticeController(this.query);

  final PracticeQuery query;
  int _generation = 0;
  bool _busy = false;
  OfflinePackStore? _packStore;

  /// True once the user answered anything (mastery changed → refresh subjects).
  bool answeredAny = false;

  QuestionBankRepository get _repo => ref.read(questionBankRepositoryProvider);

  @override
  PracticeState build() {
    ref.onDispose(() {
      final store = _packStore;
      if (store != null) unawaited(PracticeSync.flush(store));
    });
    unawaited(Future.microtask(_loadFirst));
    return const PracticeState();
  }

  Future<void> _loadFirst() async {
    final gen = ++_generation;
    _busy = true;
    state = state.copyWith(isLoadingFirst: true, clearError: true, needsPack: false);
    try {
      final pack = await _packQuestions();
      if (!ref.mounted || gen != _generation) return;
      if (pack != null) {
        state = state.copyWith(items: pack, index: 0, hasMore: false, isLoadingFirst: false, fromPack: true);
        return;
      }
      if (!ConnectivityService.instance.isOnline) {
        state = state.copyWith(isLoadingFirst: false, hasMore: false, needsPack: true, fromPack: false);
        return;
      }
      final page = await _fetch(afterId: null);
      if (!ref.mounted || gen != _generation) return;
      state = state.copyWith(
        items: page,
        index: 0,
        hasMore: page.length >= QuestionBankRepository.practicePageSize,
        isLoadingFirst: false,
        fromPack: false,
      );
    } on Object catch (e) {
      if (!ref.mounted || gen != _generation) return;
      final failure = AppFailure.from(e);
      state = state.copyWith(isLoadingFirst: false, error: failure, needsPack: failure is NetworkFailure);
    } finally {
      if (gen == _generation) _busy = false;
    }
    _maybePrefetch();
  }

  /// Questions from downloaded packs covering this selection, or null.
  Future<List<Question>?> _packQuestions() async {
    if (query.sourceId != null) return null; // packs don't carry source ids
    final OfflinePackStore store;
    try {
      store = await ref.read(offlinePackStoreProvider.future);
    } on Object catch (e) {
      debugPrint('practice: offline packs unavailable: $e');
      return null;
    }
    _packStore = store;
    unawaited(PracticeSync.flush(store)); // leftovers from a killed session
    final index = store.index();
    if (index.isEmpty) return null;
    final List<int> subjects;
    if (query.subjectId != null) {
      subjects = index.containsKey(query.subjectId) ? [query.subjectId!] : const [];
    } else if (query.topicId != null) {
      subjects = [
        for (final info in index.values)
          if (info.topicIds.contains(query.topicId)) info.subjectId,
      ];
    } else {
      // "Practise all" uses packs only when offline.
      subjects = ConnectivityService.instance.isOnline ? const [] : index.keys.toList();
    }
    if (subjects.isEmpty) return null;
    final seen = state.unseenOnly ? store.seen() : const <int>{};
    final out = <Question>[];
    for (final id in subjects) {
      final questions = await store.load(id);
      if (questions == null) continue;
      out.addAll(
        questions.where(
          (q) =>
              (query.topicId == null || q.topicId == query.topicId) &&
              // Packs downloaded before tracks existed carry no tags: keep them.
              (query.track == null || q.examTags.isEmpty || q.examTags.contains(query.track)) &&
              !seen.contains(q.id),
        ),
      );
    }
    if (out.isEmpty && !state.unseenOnly) return null;
    out.sort((a, b) => a.id.compareTo(b.id));
    return out;
  }

  Future<List<Question>> _fetch({required int? afterId}) => _repo.practiceQuestions(
    subjectId: query.subjectId,
    topicId: query.topicId,
    sourceId: query.sourceId,
    track: query.track,
    afterId: afterId,
    unseenOnly: state.unseenOnly,
  );

  /// Loads the next batch (keyset after the last loaded id).
  Future<void> loadMore() async {
    if (_busy || !state.hasMore || state.isLoadingFirst || state.items.isEmpty || state.fromPack) return;
    final gen = _generation;
    _busy = true;
    state = state.copyWith(isLoadingMore: true, clearError: true);
    try {
      final page = await _fetch(afterId: state.items.last.id);
      if (!ref.mounted || gen != _generation) return;
      final seen = {for (final q in state.items) q.id};
      state = state.copyWith(
        items: [...state.items, ...page.where((q) => seen.add(q.id))],
        hasMore: page.length >= QuestionBankRepository.practicePageSize,
        isLoadingMore: false,
      );
    } on Object catch (e) {
      if (!ref.mounted || gen != _generation) return;
      state = state.copyWith(isLoadingMore: false, error: AppFailure.from(e));
    } finally {
      if (gen == _generation) _busy = false;
    }
  }

  void _maybePrefetch() {
    if (!ref.mounted || state.error != null || state.fromPack) return;
    if (PracticePrefetch.shouldPrefetch(
      index: state.index,
      loaded: state.items.length,
      hasMore: state.hasMore,
      busy: _busy,
    )) {
      unawaited(loadMore());
    }
  }

  Future<void> retry() => state.items.isEmpty ? _loadFirst() : loadMore();

  /// Starts over from the first question (keeps the filter).
  Future<void> restart() async {
    _generation++;
    _busy = false;
    state = PracticeState(unseenOnly: state.unseenOnly);
    await _loadFirst();
  }

  Future<void> setUnseenOnly(bool value) async {
    if (value == state.unseenOnly) return;
    _generation++;
    _busy = false;
    state = PracticeState(unseenOnly: value);
    await _loadFirst();
  }

  /// Moves to question [index] (the end page is `items.length`).
  void goTo(int index) {
    final clamped = index.clamp(0, state.items.length);
    if (clamped != state.index) state = state.copyWith(index: clamped);
    _maybePrefetch();
  }

  void next() => goTo(state.index + 1);
  void previous() => goTo(state.index - 1);

  /// Grades [selected]: on device in pack mode, otherwise on the server. A
  /// locked (live daily exam) question is marked as such; other failures are
  /// rethrown for the UI.
  Future<void> answer(Question question, int selected) async {
    final existing = state.outcomes[question.id];
    if (existing != null && (existing.isResolved || existing.pending || existing.locked)) return;
    if (state.fromPack && question.correctIndex != null) {
      answeredAny = true;
      _setOutcome(
        question.id,
        PracticeOutcome(selected: selected, correctIndex: question.correctIndex, explanation: question.explanation),
      );
      await _bufferAttempt(question.id, selected);
      return;
    }
    _setOutcome(question.id, PracticeOutcome(selected: selected, pending: true));
    try {
      final verdict = await _repo.answer(question.id, selected);
      if (!ref.mounted) return;
      answeredAny = true;
      _setOutcome(
        question.id,
        PracticeOutcome(selected: selected, correctIndex: verdict.correctIndex, explanation: verdict.explanation),
      );
      unawaited(_refreshBookmark(question, verdict.correctIndex, verdict.explanation));
    } on Object catch (e) {
      if (!ref.mounted) return;
      if (isQuestionLocked(e)) {
        _setOutcome(question.id, const PracticeOutcome(locked: true));
        return;
      }
      _removeOutcome(question.id);
      rethrow;
    }
  }

  Future<void> _bufferAttempt(int questionId, int selected) async {
    final store = _packStore;
    if (store == null) return;
    try {
      final size = await store.buffer(
        PracticeAttempt(
          clientId: PracticeSync.newClientId(),
          questionId: questionId,
          selectedIndex: selected,
          answeredAt: DateTime.now(),
        ),
      );
      await store.markSeen([questionId]);
      if (size >= PracticeSync.batchSize) unawaited(PracticeSync.flush(store));
    } on Object catch (e) {
      debugPrint('practice: could not buffer answer: $e');
    }
  }

  /// "Show answer" without grading.
  Future<void> reveal(Question question) async {
    final existing = state.outcomes[question.id];
    if (existing != null && (existing.isResolved || existing.pending || existing.locked)) return;
    if (state.fromPack && question.correctIndex != null) {
      _setOutcome(
        question.id,
        PracticeOutcome(correctIndex: question.correctIndex, explanation: question.explanation, revealed: true),
      );
      return;
    }
    _setOutcome(question.id, const PracticeOutcome(pending: true, revealed: true));
    try {
      final verdict = await _repo.reveal(question.id);
      if (!ref.mounted) return;
      _setOutcome(
        question.id,
        PracticeOutcome(correctIndex: verdict.correctIndex, explanation: verdict.explanation, revealed: true),
      );
      unawaited(_refreshBookmark(question, verdict.correctIndex, verdict.explanation));
    } on Object catch (e) {
      if (!ref.mounted) return;
      if (isQuestionLocked(e)) {
        _setOutcome(question.id, const PracticeOutcome(locked: true));
        return;
      }
      _removeOutcome(question.id);
      rethrow;
    }
  }

  Future<void> _refreshBookmark(Question q, int correctIndex, String? explanation) => ref
      .read(questionBookmarksProvider.notifier)
      .refreshPayload(q.withAnswer(correctIndex: correctIndex, explanation: explanation));

  void _setOutcome(int id, PracticeOutcome outcome) {
    state = state.copyWith(outcomes: {...state.outcomes, id: outcome});
  }

  void _removeOutcome(int id) {
    state = state.copyWith(outcomes: {...state.outcomes}..remove(id));
  }
}

final practiceControllerProvider = NotifierProvider.autoDispose
    .family<PracticeController, PracticeState, PracticeQuery>(PracticeController.new);
