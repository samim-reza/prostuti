import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';

import 'fixtures.dart';

void main() {
  group('ExamResult.fromJson (live submit_exam payload)', () {
    final r = ExamResult.fromJson(resultJson());

    test('scores and counts', () {
      expect(r.sessionId, 's1');
      expect(r.kind, ExamKind.subject);
      expect(r.score, 0);
      expect(r.maxScore, 5);
      expect(r.correct, 1);
      expect(r.wrong, 2);
      expect(r.skipped, 2);
      expect(r.negativeMark, 0.5);
      expect(r.timeTakenSeconds, 6);
      expect(r.submittedAt, DateTime.parse('2026-10-03T21:12:10.536825+00:00'));
      expect(r.rank, isNull);
      expect(r.participants, isNull);
    });

    test('derived percentages', () {
      expect(r.percent, 0);
      expect(r.accuracy, closeTo(33.33, 0.01));
    });

    test('per-subject breakdown', () {
      expect(r.perSubject, hasLength(1));
      final s = r.perSubject.single;
      expect(s.nameEn, 'Computer & ICT');
      expect(s.skipped, 2);
      expect(s.accuracy, closeTo(0.2, 1e-9));
    });

    test('daily exam rank and numeric strings', () {
      final daily = ExamResult.fromJson({
        ...resultJson(kind: 'daily'),
        'score': '17.5',
        'max_score': '25',
        'rank': 3,
        'participants': 120,
      });
      expect(daily.kind, ExamKind.daily);
      expect(daily.score, 17.5);
      expect(daily.percent, 70);
      expect(daily.rank, 3);
      expect(daily.participants, 120);
    });

    test('percent is clamped (negative scores)', () {
      final neg = ExamResult.fromJson({...resultJson(), 'score': -1.5});
      expect(neg.percent, 0);
    });
  });

  group('ExamSession', () {
    test('round-trips through toJson (device cache)', () {
      final s = session(questions: 4);
      final copy = ExamSession.fromJson(s.toJson());
      expect(copy.sessionId, s.sessionId);
      expect(copy.kind, s.kind);
      expect(copy.deadlineAt, s.deadlineAt);
      expect(copy.questions.map((q) => q.id), [101, 102, 103, 104]);
      expect(copy.questions.first.correctIndex, isNull, reason: 'answers are never sent before submission');
    });

    test('unknown kinds parse as custom', () {
      expect(ExamKind.parse('model_test'), ExamKind.modelTest);
      expect(ExamKind.parse('weak_topic'), ExamKind.weakTopic);
      expect(ExamKind.parse('nope'), ExamKind.custom);
    });
  });

  group('ExamHistoryItem', () {
    test('parses and round-trips', () {
      final item = ExamHistoryItem.fromJson({...resultJson(), 'time_taken_seconds': 120});
      expect(item.skipped, 2);
      expect(item.timeTakenSeconds, 120);
      final copy = ExamHistoryItem.fromJson(item.toJson());
      expect(copy.sessionId, item.sessionId);
      expect(copy.submittedAt, item.submittedAt);
      expect(copy.kind, item.kind);
    });
  });

  group('ExamSetup', () {
    test('retake drops study-plan bookkeeping', () {
      final setup = ExamSetup.fromJson(const {
        'kind': 'subject',
        'config': {'subject_id': 7, 'count': 20, 'plan_day_id': 9, 'plan_item_key': 'x'},
      });
      expect(setup.canRetake, isTrue);
      expect(setup.retakeConfig, {'subject_id': 7, 'count': 20});
    });

    test('placement and daily exams cannot be retaken', () {
      expect(const ExamSetup(kind: ExamKind.placement).canRetake, isFalse);
      expect(const ExamSetup(kind: ExamKind.daily).canRetake, isFalse);
    });
  });

  test('Question.withAnswer fills answer details without touching the rest', () {
    final q = Question.fromJson(questionJson(5));
    final a = q.withAnswer(correctIndex: 3, explanation: 'কারণ', selectedIndex: 1);
    expect(a.correctIndex, 3);
    expect(a.explanation, 'কারণ');
    expect(a.isCorrect, isFalse);
    expect(a.stem, q.stem);
    expect(a.toJson()['correct_index'], 3);
  });

  test('AiExplanation parses the memory tip and ignores blanks', () {
    expect(AiExplanation.fromJson(const {'explanation': 'x', 'memory_tip': 'tip'}).memoryTip, 'tip');
    expect(AiExplanation.fromJson(const {'explanation': 'x', 'memory_tip': '  '}).memoryTip, isNull);
  });
}
