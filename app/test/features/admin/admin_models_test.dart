import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/features/admin/data/admin_models.dart';

const _q = AdminQuestion(
  id: 10,
  subjectId: 1,
  stem: 'বাংলাদেশের রাজধানী কোনটি?',
  options: ['ঢাকা', 'খুলনা', 'রাজশাহী', 'সিলেট'],
  correctIndex: 0,
  explanation: 'ঢাকা রাজধানী।',
);

QuestionEdit _edit({String? stem, List<String>? options, int? correct, String? explanation}) => QuestionEdit(
  stem: stem ?? _q.stem,
  options: options ?? _q.options,
  correctIndex: correct ?? _q.correctIndex,
  explanation: explanation ?? _q.explanation,
);

void main() {
  group('buildQuestionPatch', () {
    test('unchanged (even with extra whitespace) → empty', () {
      expect(buildQuestionPatch(_q, _edit()), isEmpty);
      expect(
        buildQuestionPatch(_q, _edit(stem: '  ${_q.stem}  ', options: [for (final o in _q.options) ' $o'])),
        isEmpty,
      );
    });

    test('only changed fields, trimmed', () {
      final patch = buildQuestionPatch(_q, _edit(stem: ' নতুন প্রশ্ন? ', correct: 2));
      expect(patch, {'stem': 'নতুন প্রশ্ন?', 'correct_index': 2});
    });

    test('options are sent as a full list when any option changes', () {
      final patch = buildQuestionPatch(_q, _edit(options: ['ঢাকা', 'খুলনা', 'বরিশাল ']));
      expect(patch, {
        'options': ['ঢাকা', 'খুলনা', 'বরিশাল'],
      });
    });

    test('cleared explanation is sent as empty string (RPC coalesces null)', () {
      expect(buildQuestionPatch(_q, _edit(explanation: '   ')), {'explanation': ''});
      const noExplanation = AdminQuestion(id: 1, subjectId: 1, stem: 'abc', options: ['a', 'b'], correctIndex: 0);
      expect(
        buildQuestionPatch(
          noExplanation,
          const QuestionEdit(stem: 'abc', options: ['a', 'b'], correctIndex: 0, explanation: ''),
        ),
        isEmpty,
      );
    });
  });

  test('validateQuestionEdit mirrors the table constraints', () {
    expect(validateQuestionEdit(_edit()), isNull);
    expect(validateQuestionEdit(_edit(stem: 'ab')), QuestionEditError.stemLength);
    expect(validateQuestionEdit(_edit(options: ['a'], correct: 0)), QuestionEditError.optionCount);
    expect(validateQuestionEdit(_edit(options: ['a', 'b', 'c', 'd', 'e', 'f'])), QuestionEditError.optionCount);
    expect(validateQuestionEdit(_edit(options: ['a', ' '])), QuestionEditError.emptyOption);
    expect(validateQuestionEdit(_edit(options: ['a', 'b'], correct: 3)), QuestionEditError.correctOutOfRange);
  });

  test('AdminQuestion parsing + optimistic patch', () {
    final q = AdminQuestion.fromJson(const {
      'id': 5,
      'subject_id': 2,
      'topic_id': 9,
      'stem': 'S',
      'options': ['a', 'b', 'c'],
      'correct_index': 1,
      'explanation': null,
      'status': 'published',
      'review_status': 'flagged',
      'exam_tags': ['bcs', 'ai'],
      'fact_id': 77,
      'created_at': '2026-10-01T00:00:00Z',
    });
    expect(q.reviewStatus, ReviewStatus.flagged);
    expect(q.isAiGenerated, isTrue);
    final verified = q.applyPatch({
      'review_status': 'verified',
      'options': ['x', 'y'],
      'correct_index': 0,
    });
    expect(verified.reviewStatus, ReviewStatus.verified);
    expect(verified.options, ['x', 'y']);
    expect(verified.correctIndex, 0);
    expect(verified.stem, 'S');
    expect(q.applyPatch({'status': 'rejected'}).status, 'rejected');
  });

  test('AdminStats parsing and cache hit rate', () {
    final s = AdminStats.fromJson(const {
      'users': 120,
      'active_today': 40,
      'questions': 545,
      'questions_unverified': 12,
      'daily_exam_today': true,
      'ai_calls_today': 8,
      'ai_cache_hits_today': 3,
    });
    expect(s.users, 120);
    expect(s.dailyExamToday, isTrue);
    expect(s.cacheHitPercent, 38);
    expect(const AdminStats().cacheHitPercent, 0);
  });

  test('AdminReport parsing', () {
    final r = AdminReport.fromJson(const {
      'id': 3,
      'target_type': 'post',
      'target_id': 'p1',
      'reason': 'spam',
      'details': null,
      'status': 'open',
      'created_at': '2026-10-04T08:00:00Z',
      'reporter': {'id': 'u1', 'username': 'karim', 'full_name': ' '},
      'preview': 'buy now',
    });
    expect(r.targetKey, 'post:p1');
    expect(r.reporterName, 'karim');
    expect(r.canRestore, isTrue);
    expect(
      AdminReport.fromJson(const {'target_type': 'user', 'target_id': 'x', 'reporter': <String, dynamic>{}}).canRestore,
      isFalse,
    );
  });

  test('AdminSchedule row for insert/update', () {
    final s = AdminSchedule.fromJson(const {
      'id': 1,
      'exam_type': 'bcs',
      'title_bn': ' ৫১তম বিসিএস ',
      'title_en': '51st BCS',
      'stage': '',
      'expected_date': '2026-11-28',
      'is_confirmed': false,
      'source_url': ' ',
      'notes': 'n',
      'is_active': true,
    });
    expect(s.isoDate, '2026-11-28');
    expect(s.toRow(), {
      'exam_type': 'bcs',
      'title_bn': '৫১তম বিসিএস',
      'title_en': '51st BCS',
      'stage': 'preliminary',
      'expected_date': '2026-11-28',
      'is_confirmed': false,
      'source_url': null,
      'notes': 'n',
      'is_active': true,
    });
    final moved = AdminSchedule(examType: 'bcs', titleBn: 'a', titleEn: 'a', expectedDate: DateTime(2026, 12));
    expect(s.sameDateAs(moved), isFalse);
    expect(s.sameDateAs(AdminSchedule.fromJson(const {'expected_date': '2026-11-28'})), isTrue);
    expect(moved.isNew, isTrue);
  });
}
