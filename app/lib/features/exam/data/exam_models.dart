import 'package:flutter/foundation.dart';
import 'package:prostuti/core/utils/json.dart';

/// Exam kinds supported by `start_exam` (mirrors the SQL check constraint).
enum ExamKind {
  placement,
  modelTest('model_test'),
  daily,
  subject,
  topic,
  weakTopic('weak_topic'),
  previousYear('previous_year'),
  custom;

  ExamKind([this._wire]);
  final String? _wire;

  String get wire => _wire ?? name;

  static ExamKind parse(String? v) => ExamKind.values.firstWhere((e) => e.wire == v, orElse: () => ExamKind.custom);
}

/// A question as shown to the user. [correctIndex]/[explanation]/
/// [selectedIndex] are only present after submission (review) or practice.
@immutable
class Question {
  const Question({
    required this.id,
    required this.subjectId,
    required this.stem,
    required this.options,
    this.topicId,
    this.difficulty = 2,
    this.language = 'bn',
    this.sourceRef,
    this.sourceUrl,
    this.year,
    this.correctIndex,
    this.explanation,
    this.selectedIndex,
  });

  factory Question.fromJson(Map<String, dynamic> j) => Question(
    id: j.integer('id'),
    subjectId: j.integer('subject_id'),
    topicId: j.intOrNull('topic_id'),
    stem: j.str('stem'),
    options: j.strings('options'),
    difficulty: j.integer('difficulty', 2),
    language: j.str('language', 'bn'),
    sourceRef: j.strOrNull('source_ref'),
    sourceUrl: j.strOrNull('source_url'),
    year: j.intOrNull('year'),
    correctIndex: j.intOrNull('correct_index'),
    explanation: j.strOrNull('explanation'),
    selectedIndex: j.intOrNull('selected_index'),
  );

  final int id;
  final int subjectId;
  final int? topicId;
  final String stem;
  final List<String> options;
  final int difficulty;
  final String language;
  final String? sourceRef;
  final String? sourceUrl;
  final int? year;
  final int? correctIndex;
  final String? explanation;
  final int? selectedIndex;

  bool get isAnswered => selectedIndex != null;
  bool? get isCorrect => (selectedIndex == null || correctIndex == null) ? null : selectedIndex == correctIndex;

  /// Copy with the answer details filled in (practice / reveal / bookmarks).
  Question withAnswer({int? correctIndex, String? explanation, int? selectedIndex}) => Question(
    id: id,
    subjectId: subjectId,
    topicId: topicId,
    stem: stem,
    options: options,
    difficulty: difficulty,
    language: language,
    sourceRef: sourceRef,
    sourceUrl: sourceUrl,
    year: year,
    correctIndex: correctIndex ?? this.correctIndex,
    explanation: explanation ?? this.explanation,
    selectedIndex: selectedIndex ?? this.selectedIndex,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'subject_id': subjectId,
    'topic_id': topicId,
    'stem': stem,
    'options': options,
    'difficulty': difficulty,
    'language': language,
    'source_ref': sourceRef,
    'source_url': sourceUrl,
    'year': year,
    'correct_index': correctIndex,
    'explanation': explanation,
    'selected_index': selectedIndex,
  };
}

@immutable
class ExamSession {
  const ExamSession({
    required this.sessionId,
    required this.kind,
    required this.title,
    required this.status,
    required this.startedAt,
    required this.deadlineAt,
    required this.durationSeconds,
    required this.negativeMark,
    required this.questions,
    this.config = const {},
  });

  factory ExamSession.fromJson(Map<String, dynamic> j) => ExamSession(
    sessionId: j.str('session_id'),
    kind: ExamKind.parse(j.strOrNull('kind')),
    title: j.str('title'),
    status: j.str('status', 'in_progress'),
    startedAt: j.dateOr('started_at', DateTime.now()),
    deadlineAt: j.dateOr('deadline_at', DateTime.now()),
    durationSeconds: j.integer('duration_seconds'),
    negativeMark: j.dbl('negative_mark', 0.5),
    questions: j.list('questions', Question.fromJson),
    config: j.obj('config'),
  );

  final String sessionId;
  final ExamKind kind;
  final String title;
  final String status;
  final DateTime startedAt;
  final DateTime deadlineAt;
  final int durationSeconds;
  final double negativeMark;
  final List<Question> questions;
  final Map<String, dynamic> config;

  int get total => questions.length;

  Duration get remaining {
    final d = deadlineAt.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'kind': kind.wire,
    'title': title,
    'status': status,
    'started_at': startedAt.toIso8601String(),
    'deadline_at': deadlineAt.toIso8601String(),
    'duration_seconds': durationSeconds,
    'negative_mark': negativeMark,
    'questions': questions.map((q) => q.toJson()).toList(),
    'config': config,
  };
}

@immutable
class SubjectScore {
  const SubjectScore({
    required this.subjectId,
    required this.nameBn,
    required this.nameEn,
    required this.total,
    required this.correct,
    required this.wrong,
  });

  factory SubjectScore.fromJson(Map<String, dynamic> j) => SubjectScore(
    subjectId: j.integer('subject_id'),
    nameBn: j.str('name_bn'),
    nameEn: j.str('name_en'),
    total: j.integer('total'),
    correct: j.integer('correct'),
    wrong: j.integer('wrong'),
  );

  final int subjectId;
  final String nameBn;
  final String nameEn;
  final int total;
  final int correct;
  final int wrong;

  int get skipped => total - correct - wrong;
  double get accuracy => total == 0 ? 0 : correct / total;
}

@immutable
class ExamResult {
  const ExamResult({
    required this.sessionId,
    required this.kind,
    required this.title,
    required this.score,
    required this.maxScore,
    required this.correct,
    required this.wrong,
    required this.skipped,
    required this.total,
    required this.negativeMark,
    this.timeTakenSeconds,
    this.submittedAt,
    this.perSubject = const [],
    this.rank,
    this.participants,
  });

  factory ExamResult.fromJson(Map<String, dynamic> j) => ExamResult(
    sessionId: j.str('session_id'),
    kind: ExamKind.parse(j.strOrNull('kind')),
    title: j.str('title'),
    score: j.dbl('score'),
    maxScore: j.dbl('max_score'),
    correct: j.integer('correct'),
    wrong: j.integer('wrong'),
    skipped: j.integer('skipped'),
    total: j.integer('total'),
    negativeMark: j.dbl('negative_mark', 0.5),
    timeTakenSeconds: j.intOrNull('time_taken_seconds'),
    submittedAt: j.date('submitted_at'),
    perSubject: j.list('per_subject', SubjectScore.fromJson),
    rank: j.intOrNull('rank'),
    participants: j.intOrNull('participants'),
  );

  final String sessionId;
  final ExamKind kind;
  final String title;
  final double score;
  final double maxScore;
  final int correct;
  final int wrong;
  final int skipped;
  final int total;
  final double negativeMark;
  final int? timeTakenSeconds;
  final DateTime? submittedAt;
  final List<SubjectScore> perSubject;
  final int? rank;
  final int? participants;

  double get percent => maxScore == 0 ? 0 : (score / maxScore * 100).clamp(0, 100).toDouble();
  double get accuracy => (correct + wrong) == 0 ? 0 : correct / (correct + wrong) * 100;
}

@immutable
class ExamHistoryItem {
  const ExamHistoryItem({
    required this.sessionId,
    required this.kind,
    required this.title,
    required this.score,
    required this.maxScore,
    required this.correct,
    required this.wrong,
    required this.total,
    required this.submittedAt,
    this.timeTakenSeconds,
  });

  factory ExamHistoryItem.fromJson(Map<String, dynamic> j) => ExamHistoryItem(
    sessionId: j.str('session_id'),
    kind: ExamKind.parse(j.strOrNull('kind')),
    title: j.str('title'),
    score: j.dbl('score'),
    maxScore: j.dbl('max_score'),
    correct: j.integer('correct'),
    wrong: j.integer('wrong'),
    total: j.integer('total'),
    submittedAt: j.dateOr('submitted_at', DateTime.now()),
    timeTakenSeconds: j.intOrNull('time_taken_seconds'),
  );

  final String sessionId;
  final ExamKind kind;
  final String title;
  final double score;
  final double maxScore;
  final int correct;
  final int wrong;
  final int total;
  final DateTime submittedAt;
  final int? timeTakenSeconds;

  int get skipped => (total - correct - wrong).clamp(0, total);
  double get percent => maxScore == 0 ? 0 : (score / maxScore * 100).clamp(0, 100).toDouble();

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'kind': kind.wire,
    'title': title,
    'score': score,
    'max_score': maxScore,
    'correct': correct,
    'wrong': wrong,
    'total': total,
    'submitted_at': submittedAt.toIso8601String(),
    'time_taken_seconds': timeTakenSeconds,
  };
}

/// How a session was started — used to offer "take it again".
@immutable
class ExamSetup {
  const ExamSetup({required this.kind, this.config = const {}});

  factory ExamSetup.fromJson(Map<String, dynamic> j) =>
      ExamSetup(kind: ExamKind.parse(j.strOrNull('kind')), config: j.obj('config'));

  final ExamKind kind;
  final Map<String, dynamic> config;

  /// Placement and the daily exam can be taken only once.
  bool get canRetake => kind != ExamKind.placement && kind != ExamKind.daily;

  /// Config for a fresh attempt (drops one-off study-plan bookkeeping).
  Map<String, dynamic> get retakeConfig => {
    for (final e in config.entries)
      if (e.key != 'plan_day_id' && e.key != 'plan_item_key') e.key: e.value,
  };
}

@immutable
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.username,
    required this.score,
    this.fullName,
    this.avatarUrl,
    this.timeTakenSeconds,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> j) => LeaderboardEntry(
    rank: j.integer('rank'),
    userId: j.str('user_id'),
    username: j.str('username'),
    fullName: j.strOrNull('full_name'),
    avatarUrl: j.strOrNull('avatar_url'),
    score: j.dbl('score'),
    timeTakenSeconds: j.intOrNull('time_taken_seconds'),
  );

  final int rank;
  final String userId;
  final String username;
  final String? fullName;
  final String? avatarUrl;
  final double score;
  final int? timeTakenSeconds;

  String get displayName => (fullName?.isNotEmpty ?? false) ? fullName! : username;
}

@immutable
class Leaderboard {
  const Leaderboard({required this.participants, required this.entries, this.myRank, this.myScore});

  factory Leaderboard.fromJson(Map<String, dynamic> j) => Leaderboard(
    participants: j.integer('participants'),
    entries: j.list('entries', LeaderboardEntry.fromJson),
    myRank: j.objOrNull('me')?.intOrNull('rank'),
    myScore: j.objOrNull('me')?.dblOrNull('score'),
  );

  final int participants;
  final List<LeaderboardEntry> entries;
  final int? myRank;
  final double? myScore;
}

/// Output of the `ai-explain` Edge Function.
@immutable
class AiExplanation {
  const AiExplanation({required this.explanation, this.memoryTip});

  factory AiExplanation.fromJson(Map<String, dynamic> j) {
    final tip = j.strOrNull('memory_tip')?.trim();
    return AiExplanation(explanation: j.str('explanation'), memoryTip: (tip == null || tip.isEmpty) ? null : tip);
  }

  final String explanation;
  final String? memoryTip;
}
