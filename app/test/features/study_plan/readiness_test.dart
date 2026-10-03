import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/features/study_plan/data/readiness_models.dart';

void main() {
  // Shape captured from the live `get_readiness()` RPC.
  final live = {
    'levels': [
      {'subject_id': 1, 'level': 'intermediate', 'score_pct': 0.5},
      {'subject_id': 8, 'level': 'beginner', 'score_pct': 0.2},
    ],
    'history': [
      {'date': '2026-10-04', 'readiness': 20},
      {'date': '2026-09-28', 'readiness': 13},
      {'date': '2026-10-01', 'readiness': 16},
    ],
    'coverage': 0,
    'subjects': [
      {
        'code': 'bangla',
        'color': '#0E7C66',
        'marks': 30,
        'mastery': 15,
        'name_bn': 'বাংলা ভাষা ও সাহিত্য',
        'name_en': 'Bangla Language & Literature',
        'coverage': 0,
        'subject_id': 1,
      },
      {
        'code': 'math',
        'color': '#D9480F',
        'marks': 20,
        'mastery': 15,
        'name_bn': 'গাণিতিক যুক্তি',
        'name_en': 'Mathematical Reasoning',
        'coverage': 0,
        'subject_id': 8,
      },
    ],
    'readiness': 13,
    'estimated_score': 30,
  };

  test('parses the live payload', () {
    final r = Readiness.fromJson(live);
    expect(r.readiness, 13);
    expect(r.estimatedScore, 30);
    expect(r.subjects.first.mastery, 15);
    expect(r.subjects.first.colorHex, '#0E7C66');
    expect(r.maxScore, 50, reason: 'sum of subject marks');
    expect(r.levels.first.level, SkillLevel.intermediate);
    expect(r.levels.first.scorePct, 0.5);
  });

  test('history is sorted by date and gives a weekly delta', () {
    final r = Readiness.fromJson(live);
    expect(r.history.map((h) => h.readiness), [13, 16, 20]);
    expect(r.weeklyDelta, 7);
  });

  test('normalises fractions/percentages and clamps', () {
    final r = Readiness.fromJson(const {
      'readiness': 0.42,
      'coverage': '130',
      'subjects': [
        {'subject_id': 1, 'mastery': 0.5, 'coverage': -3},
      ],
      'levels': [
        {'subject_id': 1, 'score_pct': 75},
        {'subject_id': 2, 'level': 'wizard', 'score_pct': 0.9},
      ],
    });
    expect(r.readiness, 42);
    expect(r.coverage, 100);
    expect(r.subjects.single.mastery, 50);
    expect(r.subjects.single.coverage, 0);
    expect(r.levels.first.scorePct, 0.75);
    expect(r.levels.first.level, SkillLevel.advanced, reason: 'level derived from score when missing');
    expect(r.levels.last.level, SkillLevel.beginner, reason: 'unknown level string → beginner');
  });

  test('empty payload is safe', () {
    final r = Readiness.fromJson(const {});
    expect(r.readiness, 0);
    expect(r.maxScore, 200, reason: 'BCS default when subjects are unknown');
    expect(r.weeklyDelta, isNull);
    expect(r.history, isEmpty);
  });

  test('round-trips through toJson (cache)', () {
    final r = Readiness.fromJson(live);
    final again = Readiness.fromJson(r.toJson());
    expect(again.history.map((h) => h.date), r.history.map((h) => h.date));
    expect(again.levels.first.level, SkillLevel.intermediate);
    expect(again.subjects.last.code, 'math');
  });

  test('SkillLevel thresholds mirror apply_placement_result', () {
    expect(SkillLevel.fromScore(0.39), SkillLevel.beginner);
    expect(SkillLevel.fromScore(0.4), SkillLevel.intermediate);
    expect(SkillLevel.fromScore(0.7), SkillLevel.advanced);
  });
}
