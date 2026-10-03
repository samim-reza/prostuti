import 'package:flutter/foundation.dart';
import 'package:prostuti/core/utils/json.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';

/// `public.source_kind`.
enum SourceKind {
  previousExam('previous_exam'),
  book('book'),
  newspaper('newspaper'),
  website('website'),
  aiGenerated('ai_generated'),
  curated('curated');

  SourceKind(this.wire);
  final String wire;

  static SourceKind parse(String? v) =>
      SourceKind.values.firstWhere((e) => e.wire == v, orElse: () => SourceKind.curated);
}

/// A question source (previous exam paper, book, newspaper …) with its
/// published question count — from `get_question_sources`.
@immutable
class QuestionSource {
  const QuestionSource({
    required this.id,
    required this.kind,
    required this.name,
    required this.questionCount,
    this.examType,
    this.year,
    this.publisher,
    this.url,
  });

  factory QuestionSource.fromJson(Map<String, dynamic> j) => QuestionSource(
    id: j.integer('id'),
    kind: SourceKind.parse(j.strOrNull('kind')),
    name: j.str('name'),
    examType: j.strOrNull('exam_type'),
    year: j.intOrNull('year'),
    publisher: j.strOrNull('publisher'),
    url: j.strOrNull('url'),
    questionCount: j.integer('question_count'),
  );

  final int id;
  final SourceKind kind;
  final String name;
  final String? examType;
  final int? year;
  final String? publisher;
  final String? url;
  final int questionCount;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.wire,
    'name': name,
    'exam_type': examType,
    'year': year,
    'publisher': publisher,
    'url': url,
    'question_count': questionCount,
  };
}

/// Server verdict for a practice answer (`answer_practice_question`) or a
/// revealed answer (`reveal_answer`, [isCorrect] null).
@immutable
class PracticeVerdict {
  const PracticeVerdict({required this.correctIndex, this.isCorrect, this.explanation});

  factory PracticeVerdict.fromJson(Map<String, dynamic> j) => PracticeVerdict(
    isCorrect: j['is_correct'] is bool ? j['is_correct'] as bool : null,
    correctIndex: j.integer('correct_index'),
    explanation: j.strOrNull('explanation'),
  );

  final bool? isCorrect;
  final int correctIndex;
  final String? explanation;
}

/// One entry of the wrong-answer notebook (latest graded attempt was wrong).
@immutable
class WrongAnswer {
  const WrongAnswer({required this.question, required this.attemptedAt});

  factory WrongAnswer.fromJson(Map<String, dynamic> j) =>
      WrongAnswer(question: Question.fromJson(j), attemptedAt: j.dateOr('attempted_at', DateTime.now()));

  final Question question;
  final DateTime attemptedAt;

  Map<String, dynamic> toJson() => {...question.toJson(), 'attempted_at': attemptedAt.toIso8601String()};
}
