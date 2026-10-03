import 'package:prostuti/features/exam/data/exam_models.dart';

Map<String, dynamic> questionJson(int id, {int subjectId = 7, int? topicId, String language = 'bn', int? correct}) => {
  'id': id,
  'subject_id': subjectId,
  'topic_id': topicId ?? 700 + subjectId,
  'stem': 'প্রশ্ন $id',
  'options': ['ক উত্তর', 'খ উত্তর', 'গ উত্তর', 'ঘ উত্তর'],
  'difficulty': 2,
  'language': language,
  'source_ref': null,
  'source_url': null,
  'year': null,
  'correct_index': ?correct,
};

Map<String, dynamic> sessionJson({
  String id = 's1',
  String kind = 'subject',
  int questions = 3,
  DateTime? deadline,
  String status = 'in_progress',
}) => {
  'session_id': id,
  'kind': kind,
  'title': 'বিষয়ভিত্তিক পরীক্ষা · কম্পিউটার ও তথ্যপ্রযুক্তি',
  'status': status,
  'started_at': DateTime.now().toUtc().toIso8601String(),
  'deadline_at': (deadline ?? DateTime.now().add(const Duration(minutes: 10))).toUtc().toIso8601String(),
  'duration_seconds': 600,
  'negative_mark': 0.5,
  'total': questions,
  'config': {'subject_id': 7, 'count': questions},
  'questions': [for (var i = 1; i <= questions; i++) questionJson(100 + i)],
};

ExamSession session({String id = 's1', String kind = 'subject', int questions = 3, DateTime? deadline}) =>
    ExamSession.fromJson(sessionJson(id: id, kind: kind, questions: questions, deadline: deadline));

/// Shape returned by `submit_exam` / `exam_result_json` on the live backend.
Map<String, dynamic> resultJson({String id = 's1', String kind = 'subject'}) => {
  'kind': kind,
  'rank': null,
  'score': 0.00,
  'title': 'বিষয়ভিত্তিক পরীক্ষা · কম্পিউটার ও তথ্যপ্রযুক্তি',
  'total': 5,
  'wrong': 2,
  'status': 'submitted',
  'correct': 1,
  'skipped': 2,
  'max_score': 5.00,
  'session_id': id,
  'per_subject': [
    {
      'total': 5,
      'wrong': 2,
      'correct': 1,
      'name_bn': 'কম্পিউটার ও তথ্যপ্রযুক্তি',
      'name_en': 'Computer & ICT',
      'subject_id': 7,
    },
  ],
  'participants': null,
  'submitted_at': '2026-10-03T21:12:10.536825+00:00',
  'negative_mark': 0.50,
  'time_taken_seconds': 6,
};
