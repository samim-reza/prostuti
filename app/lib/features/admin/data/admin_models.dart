import 'package:flutter/foundation.dart';
import 'package:prostuti/core/utils/json.dart';

/// `admin_dashboard()` payload.
@immutable
class AdminStats {
  const AdminStats({
    this.users = 0,
    this.activeToday = 0,
    this.postsToday = 0,
    this.questions = 0,
    this.questionsUnverified = 0,
    this.questionsFlagged = 0,
    this.facts = 0,
    this.notesToday = 0,
    this.dailyExamToday = false,
    this.activePlans = 0,
    this.openReports = 0,
    this.aiCallsToday = 0,
    this.aiCacheHitsToday = 0,
  });

  factory AdminStats.fromJson(Map<String, dynamic> j) => AdminStats(
    users: j.integer('users'),
    activeToday: j.integer('active_today'),
    postsToday: j.integer('posts_today'),
    questions: j.integer('questions'),
    questionsUnverified: j.integer('questions_unverified'),
    questionsFlagged: j.integer('questions_flagged'),
    facts: j.integer('facts'),
    notesToday: j.integer('notes_today'),
    dailyExamToday: j.boolean('daily_exam_today'),
    activePlans: j.integer('active_plans'),
    openReports: j.integer('open_reports'),
    aiCallsToday: j.integer('ai_calls_today'),
    aiCacheHitsToday: j.integer('ai_cache_hits_today'),
  );

  final int users;
  final int activeToday;
  final int postsToday;
  final int questions;
  final int questionsUnverified;
  final int questionsFlagged;
  final int facts;
  final int notesToday;
  final bool dailyExamToday;
  final int activePlans;
  final int openReports;
  final int aiCallsToday;
  final int aiCacheHitsToday;

  /// Share of today's AI calls answered from the semantic cache (0…100).
  int get cacheHitPercent => aiCallsToday == 0 ? 0 : (aiCacheHitsToday * 100 / aiCallsToday).round();
}

/// Review queue filter (`questions.review_status`).
enum ReviewStatus {
  unverified,
  flagged,
  verified;

  static ReviewStatus parse(String? v) =>
      ReviewStatus.values.firstWhere((e) => e.name == v, orElse: () => ReviewStatus.unverified);
}

/// A question as staff see it (with the answer key and moderation state).
@immutable
class AdminQuestion {
  const AdminQuestion({
    required this.id,
    required this.subjectId,
    required this.stem,
    required this.options,
    required this.correctIndex,
    this.topicId,
    this.explanation,
    this.difficulty = 2,
    this.language = 'bn',
    this.sourceRef,
    this.sourceUrl,
    this.year,
    this.status = 'published',
    this.reviewStatus = ReviewStatus.unverified,
    this.examTags = const [],
    this.factId,
    this.createdAt,
  });

  factory AdminQuestion.fromJson(Map<String, dynamic> j) => AdminQuestion(
    id: j.integer('id'),
    subjectId: j.integer('subject_id'),
    topicId: j.intOrNull('topic_id'),
    stem: j.str('stem'),
    options: j.strings('options'),
    correctIndex: j.integer('correct_index'),
    explanation: j.strOrNull('explanation'),
    difficulty: j.integer('difficulty', 2),
    language: j.str('language', 'bn'),
    sourceRef: j.strOrNull('source_ref'),
    sourceUrl: j.strOrNull('source_url'),
    year: j.intOrNull('year'),
    status: j.str('status', 'published'),
    reviewStatus: ReviewStatus.parse(j.strOrNull('review_status')),
    examTags: j.strings('exam_tags'),
    factId: j.intOrNull('fact_id'),
    createdAt: j.date('created_at'),
  );

  final int id;
  final int subjectId;
  final int? topicId;
  final String stem;
  final List<String> options;
  final int correctIndex;
  final String? explanation;
  final int difficulty;
  final String language;
  final String? sourceRef;
  final String? sourceUrl;
  final int? year;
  final String status;
  final ReviewStatus reviewStatus;
  final List<String> examTags;
  final int? factId;
  final DateTime? createdAt;

  bool get isAiGenerated => factId != null || examTags.contains('ai');

  /// Applies an `admin_update_question` patch locally (optimistic UI).
  AdminQuestion applyPatch(Map<String, dynamic> p) => AdminQuestion(
    id: id,
    subjectId: subjectId,
    topicId: p.intOrNull('topic_id') ?? topicId,
    stem: p.strOrNull('stem') ?? stem,
    options: p['options'] is List ? p.strings('options') : options,
    correctIndex: p.intOrNull('correct_index') ?? correctIndex,
    explanation: p.strOrNull('explanation') ?? explanation,
    difficulty: p.intOrNull('difficulty') ?? difficulty,
    language: language,
    sourceRef: sourceRef,
    sourceUrl: sourceUrl,
    year: year,
    status: p.strOrNull('status') ?? status,
    reviewStatus: p.strOrNull('review_status') == null
        ? reviewStatus
        : ReviewStatus.parse(p.strOrNull('review_status')),
    examTags: examTags,
    factId: factId,
    createdAt: createdAt,
  );
}

/// Edited values from the question editor.
@immutable
class QuestionEdit {
  const QuestionEdit({required this.stem, required this.options, required this.correctIndex, this.explanation});

  final String stem;
  final List<String> options;
  final int correctIndex;
  final String? explanation;
}

/// Why an edit can't be saved (mirrors the `questions` check constraints).
enum QuestionEditError { stemLength, optionCount, emptyOption, correctOutOfRange }

QuestionEditError? validateQuestionEdit(QuestionEdit e) {
  final stem = e.stem.trim();
  if (stem.length < 3 || stem.length > 2000) return QuestionEditError.stemLength;
  if (e.options.length < 2 || e.options.length > 5) return QuestionEditError.optionCount;
  if (e.options.any((o) => o.trim().isEmpty)) return QuestionEditError.emptyOption;
  if (e.correctIndex < 0 || e.correctIndex >= e.options.length) return QuestionEditError.correctOutOfRange;
  return null;
}

/// Minimal `p_patch` for `admin_update_question`: only fields that changed,
/// trimmed. Empty map → nothing to update.
Map<String, dynamic> buildQuestionPatch(AdminQuestion original, QuestionEdit edit) {
  final patch = <String, dynamic>{};
  final stem = edit.stem.trim();
  if (stem != original.stem.trim()) patch['stem'] = stem;
  final options = edit.options.map((o) => o.trim()).toList(growable: false);
  if (!listEquals(options, original.options.map((o) => o.trim()).toList())) patch['options'] = options;
  if (edit.correctIndex != original.correctIndex) patch['correct_index'] = edit.correctIndex;
  final explanation = edit.explanation?.trim() ?? '';
  final before = original.explanation?.trim() ?? '';
  // The RPC coalesces nulls, so a cleared explanation is sent as ''.
  if (explanation != before) patch['explanation'] = explanation;
  return patch;
}

/// One moderation report (`admin_list_reports`).
@immutable
class AdminReport {
  const AdminReport({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.details,
    this.preview,
    this.reporterId,
    this.reporterName,
    this.reporterUsername,
  });

  factory AdminReport.fromJson(Map<String, dynamic> j) {
    final reporter = j.obj('reporter');
    final fullName = reporter.strOrNull('full_name');
    return AdminReport(
      id: j.integer('id'),
      targetType: j.str('target_type'),
      targetId: j.str('target_id'),
      reason: j.str('reason', 'other'),
      details: j.strOrNull('details'),
      status: j.str('status', 'open'),
      createdAt: j.dateOr('created_at', DateTime.now()),
      preview: j.strOrNull('preview'),
      reporterId: reporter.strOrNull('id'),
      reporterName: (fullName?.trim().isNotEmpty ?? false) ? fullName!.trim() : reporter.strOrNull('username'),
      reporterUsername: reporter.strOrNull('username'),
    );
  }

  final int id;
  final String targetType;
  final String targetId;
  final String reason;
  final String? details;
  final String status;
  final DateTime createdAt;
  final String? preview;
  final String? reporterId;
  final String? reporterName;
  final String? reporterUsername;

  /// `admin_resolve_report` resolves every open report on the same target.
  String get targetKey => '$targetType:$targetId';

  /// Restoring is only implemented for posts and comments.
  bool get canRestore => targetType == 'post' || targetType == 'comment';
}

/// `exam_schedules` row as admins edit it.
@immutable
class AdminSchedule {
  const AdminSchedule({
    required this.examType,
    required this.titleBn,
    required this.titleEn,
    required this.expectedDate,
    this.id,
    this.stage = 'preliminary',
    this.isConfirmed = false,
    this.sourceUrl,
    this.notes,
    this.isActive = true,
  });

  factory AdminSchedule.fromJson(Map<String, dynamic> j) => AdminSchedule(
    id: j.intOrNull('id'),
    examType: j.str('exam_type', 'bcs'),
    titleBn: j.str('title_bn'),
    titleEn: j.str('title_en'),
    stage: j.str('stage', 'preliminary'),
    expectedDate: j.dateOr('expected_date', DateTime.now()),
    isConfirmed: j.boolean('is_confirmed'),
    sourceUrl: j.strOrNull('source_url'),
    notes: j.strOrNull('notes'),
    isActive: j.boolean('is_active', true),
  );

  static const columns =
      'id, exam_type, title_bn, title_en, stage, expected_date, is_confirmed, source_url, notes, is_active';

  final int? id;
  final String examType;
  final String titleBn;
  final String titleEn;
  final String stage;
  final DateTime expectedDate;
  final bool isConfirmed;
  final String? sourceUrl;
  final String? notes;
  final bool isActive;

  bool get isNew => id == null;

  /// `yyyy-MM-dd` (Postgres `date`).
  String get isoDate =>
      '${expectedDate.year.toString().padLeft(4, '0')}-${expectedDate.month.toString().padLeft(2, '0')}-'
      '${expectedDate.day.toString().padLeft(2, '0')}';

  /// Writable columns for insert/update.
  Map<String, dynamic> toRow() => {
    'exam_type': examType,
    'title_bn': titleBn.trim(),
    'title_en': titleEn.trim(),
    'stage': stage.trim().isEmpty ? 'preliminary' : stage.trim(),
    'expected_date': isoDate,
    'is_confirmed': isConfirmed,
    'source_url': (sourceUrl?.trim().isEmpty ?? true) ? null : sourceUrl!.trim(),
    'notes': (notes?.trim().isEmpty ?? true) ? null : notes!.trim(),
    'is_active': isActive,
  };

  bool sameDateAs(AdminSchedule other) => isoDate == other.isoDate;
}
