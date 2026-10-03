import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/features/exam/application/exam_answers.dart';

void main() {
  group('ExamAnswerSheet reducer', () {
    const empty = ExamAnswerSheet();

    test('select records an answer', () {
      final s = empty.select(1, 2);
      expect(s.selectedFor(1), 2);
      expect(s.answeredCount, 1);
      expect(s.markOf(1), QuestionMark.answered);
      expect(empty.answeredCount, 0, reason: 'immutable');
    });

    test('selecting another option changes the answer', () {
      final s = empty.select(1, 2).select(1, 0);
      expect(s.selectedFor(1), 0);
      expect(s.answeredCount, 1);
    });

    test('selecting the same option again clears it', () {
      final s = empty.select(1, 2).select(1, 2);
      expect(s.selectedFor(1), isNull);
      expect(s.answeredCount, 0);
      expect(s.markOf(1), QuestionMark.unanswered);
    });

    test('clear removes only that answer', () {
      final s = empty.select(1, 1).select(2, 3).clear(1);
      expect(s.answers, {2: 3});
      expect(identical(s.clear(99), s), isTrue);
    });

    test('flags toggle independently of answers', () {
      var s = empty.toggleFlag(5);
      expect(s.isFlagged(5), isTrue);
      expect(s.markOf(5), QuestionMark.flagged);
      s = s.select(5, 0);
      expect(s.markOf(5), QuestionMark.answeredFlagged);
      s = s.toggleFlag(5);
      expect(s.isFlagged(5), isFalse);
      expect(s.markOf(5), QuestionMark.answered);
      expect(s.flaggedCount, 0);
    });

    test('skippedOf counts unanswered questions', () {
      final s = empty.select(1, 0).select(2, 1);
      expect(s.skippedOf(5), 3);
      expect(s.skippedOf(1), 0, reason: 'never negative');
    });

    test('retainValid drops unknown questions and out-of-range options', () {
      const s = ExamAnswerSheet(answers: {1: 0, 2: 7, 3: 1}, flagged: {1, 9});
      final valid = s.retainValid({1: 4, 2: 4});
      expect(valid.answers, {1: 0});
      expect(valid.flagged, {1});
    });

    test('firstPending finds the first unanswered or flagged question', () {
      final s = empty.select(1, 0).select(2, 0).toggleFlag(2);
      expect(s.firstPending([1, 2, 3]), 1);
      expect(empty.select(1, 0).firstPending([1]), isNull);
    });

    test('value equality', () {
      expect(empty.select(1, 2).toggleFlag(3), empty.toggleFlag(3).select(1, 2));
      expect(empty.select(1, 2) == empty.select(1, 3), isFalse);
    });
  });
}
