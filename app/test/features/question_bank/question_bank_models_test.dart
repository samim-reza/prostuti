import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/features/question_bank/data/question_bank_models.dart';

import '../exam/fixtures.dart';

void main() {
  test('QuestionSource parses the live get_question_sources row', () {
    final s = QuestionSource.fromJson(const {
      'id': 1,
      'url': null,
      'kind': 'curated',
      'name': 'প্রস্তুতি কিউরেটেড প্রশ্নব্যাংক',
      'year': null,
      'exam_type': null,
      'publisher': 'Prostuti',
      'question_count': 545,
    });
    expect(s.kind, SourceKind.curated);
    expect(s.questionCount, 545);
    expect(QuestionSource.fromJson(s.toJson()).name, s.name);
    expect(SourceKind.parse('previous_exam'), SourceKind.previousExam);
  });

  test('PracticeVerdict for answers and reveals', () {
    final answer = PracticeVerdict.fromJson(const {'is_correct': true, 'correct_index': 2, 'explanation': 'x'});
    expect(answer.isCorrect, isTrue);
    expect(answer.correctIndex, 2);
    final reveal = PracticeVerdict.fromJson(const {'correct_index': 0, 'explanation': null});
    expect(reveal.isCorrect, isNull);
    expect(reveal.explanation, isNull);
  });

  test('WrongAnswer keeps the user answer and round-trips', () {
    final w = WrongAnswer.fromJson({
      ...questionJson(147, correct: 3),
      'explanation': 'MICR',
      'selected_index': 0,
      'attempted_at': '2026-10-03T21:12:10.536825+00:00',
    });
    expect(w.question.selectedIndex, 0);
    expect(w.question.correctIndex, 3);
    expect(w.question.isCorrect, isFalse);
    final copy = WrongAnswer.fromJson(w.toJson());
    expect(copy.attemptedAt, w.attemptedAt);
    expect(copy.question.explanation, 'MICR');
  });
}
