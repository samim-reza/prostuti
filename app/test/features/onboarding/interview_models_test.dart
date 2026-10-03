import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/features/onboarding/application/interview_controller.dart';
import 'package:prostuti/features/onboarding/application/placement_groups.dart';
import 'package:prostuti/features/onboarding/data/interview_models.dart';
import 'package:prostuti/features/study_plan/data/readiness_models.dart';

void main() {
  group('AiFollowup.listFrom', () {
    test('takes at most two non-empty questions', () {
      final list = AiFollowup.listFrom([
        {'id': 'f1', 'q': 'চাকরির পাশাপাশি কখন পড়েন?'},
        {'id': 'f2', 'q': '   '},
        {'question': 'Which book?'},
        'Plain string question',
      ]);
      expect(list.map((f) => f.id), ['f1', 'f3']);
      expect(list.last.question, 'Which book?');
    });

    test('garbage → empty', () {
      expect(AiFollowup.listFrom(null), isEmpty);
      expect(AiFollowup.listFrom({'q': 'x'}), isEmpty);
    });
  });

  group('AiProfile.parse', () {
    test('accepts the documented {profile: {...}} shape', () {
      final p = AiProfile.parse({
        'profile': {
          'summary_bn': 'আপনি গণিতে ভালো।',
          'strengths': ['গণিত', ''],
          'focus_areas': ['ইংরেজি'],
          'recommended_daily_minutes': 150,
        },
      });
      expect(p!.summary, 'আপনি গণিতে ভালো।');
      expect(p.strengths, ['গণিত']);
      expect(p.focusAreas, ['ইংরেজি']);
      expect(p.recommendedDailyMinutes, 150);
    });

    test('bare object, English summary, out-of-range minutes ignored', () {
      final p = AiProfile.parse({'summary': 'Strong in maths.', 'recommended_daily_minutes': 5000});
      expect(p!.summary, 'Strong in maths.');
      expect(p.recommendedDailyMinutes, isNull);
    });

    test('no summary → null', () {
      expect(
        AiProfile.parse({
          'profile': {'strengths': <Object>[]},
        }),
        isNull,
      );
      expect(AiProfile.parse('nope'), isNull);
    });
  });

  group('parseGraduationYear', () {
    final now = DateTime(2026, 10, 4);
    test('ASCII and Bangla digits', () {
      expect(parseGraduationYear('2022', now: now), 2022);
      expect(parseGraduationYear('২০২৪', now: now), 2024);
    });
    test('rejects implausible years', () {
      expect(parseGraduationYear('1950', now: now), isNull);
      expect(parseGraduationYear('2040', now: now), isNull);
      expect(parseGraduationYear('abcd', now: now), isNull);
    });
  });

  group('groupLevels', () {
    test('one row per placement group, in test order', () {
      final r = Readiness.fromJson(const {
        'subjects': [
          {'subject_id': 1, 'code': 'bangla'},
          {'subject_id': 2, 'code': 'english'},
          {'subject_id': 3, 'code': 'bd_affairs'},
          {'subject_id': 4, 'code': 'international'},
          {'subject_id': 8, 'code': 'math'},
          {'subject_id': 9, 'code': 'mental_ability'},
        ],
        'levels': [
          {'subject_id': 9, 'level': 'advanced', 'score_pct': 0.8},
          {'subject_id': 8, 'level': 'advanced', 'score_pct': 0.8},
          {'subject_id': 3, 'level': 'beginner', 'score_pct': 0.3},
          {'subject_id': 4, 'level': 'beginner', 'score_pct': 0.3},
          {'subject_id': 1, 'level': 'intermediate', 'score_pct': 0.5},
          {'subject_id': 77, 'level': 'advanced', 'score_pct': 1},
        ],
      });
      final groups = groupLevels(r);
      expect(groups.map((g) => g.group), [PlacementGroup.bangla, PlacementGroup.math, PlacementGroup.gk]);
      expect(groups[1].level, SkillLevel.advanced);
      expect(groups[1].scorePct, closeTo(0.8, 1e-9));
      expect(groups[2].level, SkillLevel.beginner);
    });

    test('skipped placement → no rows', () {
      expect(groupLevels(Readiness.fromJson(const {'levels': <Object>[]})), isEmpty);
    });
  });
}
