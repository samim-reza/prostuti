import 'package:flutter/foundation.dart';
import 'package:prostuti/core/utils/json.dart';
import 'package:prostuti/features/study_plan/data/plan_models.dart';

/// Placement-test level of a subject (mirrors `user_subject_levels.level`).
enum SkillLevel {
  beginner,
  intermediate,
  advanced;

  static SkillLevel parse(String? v) => values.firstWhere((e) => e.name == v, orElse: () => beginner);

  /// Same thresholds as `apply_placement_result` (≥70 % advanced, ≥40 % intermediate).
  static SkillLevel fromScore(double fraction) => fraction >= 0.7
      ? advanced
      : fraction >= 0.4
      ? intermediate
      : beginner;
}

/// Normalises a 0–100 percentage that might arrive as a 0–1 fraction.
int _percent(Object? raw) {
  final n = raw is num ? raw.toDouble() : double.tryParse('$raw');
  if (n == null || n.isNaN) return 0;
  final v = (n > 0 && n < 1 && n != n.roundToDouble()) ? n * 100 : n;
  return v.round().clamp(0, 100);
}

/// Normalises a 0–1 fraction that might arrive as a 0–100 percentage.
double _fraction(Object? raw) {
  final n = raw is num ? raw.toDouble() : double.tryParse('$raw');
  if (n == null || n.isNaN) return 0;
  return (n > 1 ? n / 100 : n).clamp(0, 1).toDouble();
}

@immutable
class SubjectReadiness {
  const SubjectReadiness({
    required this.subjectId,
    required this.code,
    required this.nameBn,
    required this.nameEn,
    this.colorHex,
    this.marks = 0,
    this.mastery = 0,
    this.coverage = 0,
  });

  factory SubjectReadiness.fromJson(Map<String, dynamic> j) => SubjectReadiness(
    subjectId: j.integer('subject_id', j.integer('id')),
    code: j.str('code'),
    nameBn: j.str('name_bn'),
    nameEn: j.str('name_en', j.str('name_bn')),
    colorHex: j.strOrNull('color'),
    marks: j.integer('marks', j.integer('bcs_marks')),
    mastery: _percent(j['mastery']),
    coverage: _percent(j['coverage']),
  );

  final int subjectId;
  final String code;
  final String nameBn;
  final String nameEn;
  final String? colorHex;
  final int marks;

  /// 0–100.
  final int mastery;

  /// 0–100.
  final int coverage;

  Map<String, dynamic> toJson() => {
    'subject_id': subjectId,
    'code': code,
    'name_bn': nameBn,
    'name_en': nameEn,
    'color': colorHex,
    'marks': marks,
    'mastery': mastery,
    'coverage': coverage,
  };
}

@immutable
class ReadinessPoint {
  const ReadinessPoint({required this.date, required this.readiness});

  final DateTime date;
  final int readiness;

  Map<String, dynamic> toJson() => {'date': date.toIso8601String(), 'readiness': readiness};
}

@immutable
class SubjectLevel {
  const SubjectLevel({required this.subjectId, required this.level, required this.scorePct});

  factory SubjectLevel.fromJson(Map<String, dynamic> j) {
    final score = _fraction(j['score_pct']);
    return SubjectLevel(
      subjectId: j.integer('subject_id'),
      level: j.strOrNull('level') == null ? SkillLevel.fromScore(score) : SkillLevel.parse(j.strOrNull('level')),
      scorePct: score,
    );
  }

  final int subjectId;
  final SkillLevel level;

  /// 0…1.
  final double scorePct;

  Map<String, dynamic> toJson() => {'subject_id': subjectId, 'level': level.name, 'score_pct': scorePct};
}

/// `get_readiness()` — how ready the user is for the final exam.
@immutable
class Readiness {
  const Readiness({
    this.readiness = 0,
    this.coverage = 0,
    this.estimatedScore = 0,
    this.subjects = const [],
    this.history = const [],
    this.levels = const [],
  });

  factory Readiness.fromJson(Map<String, dynamic> j) {
    final history = <ReadinessPoint>[];
    for (final e in (j['history'] is List ? j['history'] as List : const <Object?>[])) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final date = parsePlanDate(m['date'] ?? m['snap_date']);
      if (date == null) continue;
      history.add(ReadinessPoint(date: date, readiness: _percent(m['readiness'])));
    }
    history.sort((a, b) => a.date.compareTo(b.date));
    return Readiness(
      readiness: _percent(j['readiness']),
      coverage: _percent(j['coverage']),
      estimatedScore: j.integer('estimated_score').clamp(0, 1000),
      subjects: j.list('subjects', SubjectReadiness.fromJson),
      history: history,
      levels: j.list('levels', SubjectLevel.fromJson),
    );
  }

  /// 0–100.
  final int readiness;

  /// 0–100.
  final int coverage;

  /// Out of [maxScore] (BCS preliminary: 200).
  final int estimatedScore;
  final List<SubjectReadiness> subjects;
  final List<ReadinessPoint> history;
  final List<SubjectLevel> levels;

  int get maxScore {
    final sum = subjects.fold<int>(0, (s, e) => s + e.marks);
    return sum > 0 ? sum : 200;
  }

  /// Readiness change versus the earliest snapshot of the last week.
  int? get weeklyDelta {
    if (history.length < 2) return null;
    final last = history.last;
    final weekAgo = last.date.subtract(const Duration(days: 7));
    final base = history.firstWhere((p) => !p.date.isBefore(weekAgo), orElse: () => history.first);
    if (identical(base, last)) return null;
    return last.readiness - base.readiness;
  }

  Map<String, dynamic> toJson() => {
    'readiness': readiness,
    'coverage': coverage,
    'estimated_score': estimatedScore,
    'subjects': subjects.map((s) => s.toJson()).toList(),
    'history': history.map((h) => h.toJson()).toList(),
    'levels': levels.map((l) => l.toJson()).toList(),
  };
}
