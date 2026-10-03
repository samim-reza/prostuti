import 'package:flutter/foundation.dart';

/// How a question appears in the navigator grid.
enum QuestionMark { unanswered, answered, flagged, answeredFlagged }

/// Immutable answer sheet of an exam in progress (pure reducer — no I/O).
///
/// * selecting an option records it; selecting the **same** option again
///   clears it (with −0.5 negative marking, un-answering is a real strategy);
/// * selecting a different option changes the answer;
/// * flags ("review later") are independent of answers.
@immutable
class ExamAnswerSheet {
  const ExamAnswerSheet({this.answers = const {}, this.flagged = const {}});

  /// question id → selected option index.
  final Map<int, int> answers;

  /// Question ids marked for review.
  final Set<int> flagged;

  int? selectedFor(int questionId) => answers[questionId];
  bool isFlagged(int questionId) => flagged.contains(questionId);
  int get answeredCount => answers.length;
  int get flaggedCount => flagged.length;
  int skippedOf(int total) => (total - answers.length).clamp(0, total);

  QuestionMark markOf(int questionId) {
    final answered = answers.containsKey(questionId);
    final flag = flagged.contains(questionId);
    if (answered && flag) return QuestionMark.answeredFlagged;
    if (flag) return QuestionMark.flagged;
    if (answered) return QuestionMark.answered;
    return QuestionMark.unanswered;
  }

  /// Records [optionIndex] for [questionId]; tapping the current answer
  /// again clears it.
  ExamAnswerSheet select(int questionId, int optionIndex) {
    final next = Map<int, int>.of(answers);
    if (next[questionId] == optionIndex) {
      next.remove(questionId);
    } else {
      next[questionId] = optionIndex;
    }
    return ExamAnswerSheet(answers: Map.unmodifiable(next), flagged: flagged);
  }

  ExamAnswerSheet clear(int questionId) {
    if (!answers.containsKey(questionId)) return this;
    final next = Map<int, int>.of(answers)..remove(questionId);
    return ExamAnswerSheet(answers: Map.unmodifiable(next), flagged: flagged);
  }

  ExamAnswerSheet toggleFlag(int questionId) {
    final next = Set<int>.of(flagged);
    if (!next.remove(questionId)) next.add(questionId);
    return ExamAnswerSheet(answers: answers, flagged: Set.unmodifiable(next));
  }

  /// Drops answers/flags for questions that are not part of the session
  /// (stale device cache) and out-of-range option indexes.
  ExamAnswerSheet retainValid(Map<int, int> optionCounts) {
    return ExamAnswerSheet(
      answers: Map.unmodifiable({
        for (final e in answers.entries)
          if (optionCounts.containsKey(e.key) && e.value >= 0 && e.value < optionCounts[e.key]!) e.key: e.value,
      }),
      flagged: Set.unmodifiable(flagged.where(optionCounts.containsKey)),
    );
  }

  /// First question (in [order]) that is unanswered or flagged, else null.
  int? firstPending(List<int> order) {
    for (var i = 0; i < order.length; i++) {
      final id = order[i];
      if (!answers.containsKey(id) || flagged.contains(id)) return i;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is ExamAnswerSheet && mapEquals(other.answers, answers) && setEquals(other.flagged, flagged);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(answers.entries.map((e) => Object.hash(e.key, e.value))),
    Object.hashAllUnordered(flagged),
  );
}
