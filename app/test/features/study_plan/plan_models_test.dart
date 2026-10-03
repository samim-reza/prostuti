import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/features/study_plan/data/plan_models.dart';

void main() {
  group('PlanItem', () {
    test('parses a full item', () {
      final item = PlanItem.fromJson(const {
        'key': 'd1-1',
        'type': 'practice',
        'subject_id': 1,
        'topic_id': '102',
        'title_bn': 'সন্ধি অনুশীলন',
        'title_en': 'Sandhi practice',
        'minutes': 30,
        'count': 20,
        'done': true,
      });
      expect(item.key, 'd1-1');
      expect(item.type, PlanItemType.practice);
      expect(item.topicId, 102);
      expect(item.done, isTrue);
      expect(item.title(bangla: true), 'সন্ধি অনুশীলন');
      expect(item.title(bangla: false), 'Sandhi practice');
      expect(item.canComplete, isTrue);
    });

    test('is defensive about missing/odd fields', () {
      final item = PlanItem.fromJson(const {'type': 'teleport', 'done': 'true'});
      expect(item.type, PlanItemType.other);
      expect(item.key, isEmpty);
      expect(item.canComplete, isFalse, reason: 'no key → the server cannot mark it');
      expect(item.done, isTrue);
      expect(item.title(bangla: false), isEmpty, reason: 'falls back to Bangla (empty here)');
    });

    test('rest items cannot be ticked', () {
      expect(const PlanItem(key: 'r', type: PlanItemType.rest, titleBn: 'বিশ্রাম').canComplete, isFalse);
    });

    test('listFrom skips garbage and accepts JSON strings', () {
      expect(PlanItem.listFrom(null), isEmpty);
      expect(PlanItem.listFrom('not json'), isEmpty);
      expect(
        PlanItem.listFrom([
          1,
          'x',
          null,
          {'key': 'a', 'type': 'read', 'title_bn': 'পড়া'},
        ]),
        hasLength(1),
      );
      final fromString = PlanItem.listFrom('[{"key":"k","type":"exam","title_bn":"পরীক্ষা"}]');
      expect(fromString.single.type, PlanItemType.exam);
    });

    test('English title falls back to Bangla when blank', () {
      const item = PlanItem(key: 'k', type: PlanItemType.read, titleBn: 'বাংলা', titleEn: '  ');
      expect(item.title(bangla: false), 'বাংলা');
    });
  });

  group('PlanDay', () {
    final json = {
      'id': 7,
      'plan_id': 'p1',
      'day_date': '2026-10-04',
      'day_index': 3,
      'kind': 'weak_topic_exam',
      'title_bn': 'দুর্বল টপিক দিবস',
      'title_en': 'Weak-topic day',
      'items': [
        {'key': 'a', 'type': 'exam', 'title_bn': 'পরীক্ষা', 'minutes': 20, 'done': true},
        {'key': 'b', 'type': 'revise', 'title_bn': 'রিভিশন', 'minutes': 40},
      ],
      'target_minutes': 0,
      'completed_items': 1,
      'total_items': 2,
      'status': 'partial',
      'weak_topics': [
        {'topic_id': 103, 'name_bn': 'সন্ধি', 'name_en': 'Sandhi', 'subject_id': 1, 'mastery': 0.21},
      ],
    };

    test('parses the routine row', () {
      final day = PlanDay.fromJson(json);
      expect(day.id, 7);
      expect(day.date, DateTime.utc(2026, 10, 4));
      expect(day.kind, PlanDayKind.weakTopicExam);
      expect(day.title(bangla: false), 'Weak-topic day');
      expect(day.doneCount, 1);
      expect(day.itemCount, 2);
      expect(day.progress, 0.5);
      expect(day.plannedMinutes, 60, reason: 'target 0 → sum of item minutes');
      expect(day.weakTopics.single.name(bangla: false), 'Sandhi');
      expect(day.status, PlanDayStatus.partial);
    });

    test('round-trips through toJson (cache)', () {
      final day = PlanDay.fromJson(json);
      final again = PlanDay.fromJson(day.toJson());
      expect(again.date, day.date);
      expect(again.items.map((i) => i.done), [true, false]);
      expect(again.weakTopics.single.topicId, 103);
      expect(again.titleEn, 'Weak-topic day');
    });

    test('unlock check uses the Bangladesh calendar day', () {
      final day = PlanDay.fromJson(json);
      expect(day.isUnlockedOn(DateTime.utc(2026, 10, 4)), isTrue);
      expect(day.isUnlockedOn(DateTime.utc(2026, 10, 3)), isFalse);
    });

    test('unknown kind/status and missing items do not crash', () {
      final day = PlanDay.fromJson(const {'id': '9', 'kind': 'party', 'status': '???', 'items': 'oops'});
      expect(day.id, 9);
      expect(day.kind, PlanDayKind.other);
      expect(day.status, PlanDayStatus.pending);
      expect(day.items, isEmpty);
      expect(day.progress, 0);
    });
  });

  group('TodayRoutine', () {
    test('no plan', () {
      final r = TodayRoutine.fromJson(const {'plan': null, 'today': null, 'has_plan': false, 'upcoming': <Object>[]});
      expect(r.hasPlan, isFalse);
      expect(r.today, isNull);
    });

    test('with plan, today and upcoming', () {
      final r = TodayRoutine.fromJson(const {
        'has_plan': true,
        'plan': {
          'id': 'p',
          'exam_date': '2027-05-14',
          'start_date': '2026-10-04',
          'days_left': 222,
          'daily_minutes': 120,
          'version': 2,
        },
        'today': {'id': 1, 'day_date': '2026-10-04', 'kind': 'study', 'title_bn': 'আজ', 'items': <Object>[]},
        'upcoming': [
          {'id': 2, 'day_date': '2026-10-05', 'kind': 'revision', 'title_bn': 'কাল', 'target_minutes': 90},
          {'id': 3, 'day_date': '2026-10-06', 'kind': 'model_test', 'title_bn': 'পরশু'},
        ],
      });
      expect(r.hasPlan, isTrue);
      expect(r.plan!.daysLeft, 222);
      expect(r.plan!.examDate, DateTime.utc(2027, 5, 14));
      expect(r.today!.kind, PlanDayKind.study);
      expect(r.upcoming.map((d) => d.kind), [PlanDayKind.revision, PlanDayKind.modelTest]);
      final cached = TodayRoutine.fromJson(r.toJson());
      expect(cached.upcoming.first.targetMinutes, 90);
      expect(cached.plan!.version, 2);
    });

    test('has_plan inferred from plan when the flag is missing', () {
      expect(
        TodayRoutine.fromJson(const {
          'plan': {'id': 'x'},
        }).hasPlan,
        isTrue,
      );
    });
  });

  group('PlanSummary & tips', () {
    test('parses phases and sorts milestones by date', () {
      final s = PlanSummary.parse(const {
        'phases': [
          {
            'key': 'foundation',
            'name_bn': 'ভিত্তি',
            'name_en': 'Foundation',
            'start_date': '2026-10-04',
            'end_date': '2026-12-31',
            'focus_bn': 'মূল বিষয়',
          },
          {'key': 'empty'},
        ],
        'milestones': [
          {'date': '2027-03-01', 'title_bn': 'দ্বিতীয়'},
          {'date': '2026-11-01', 'title_bn': 'প্রথম'},
          {'title_bn': 'তারিখহীন'},
        ],
        'total_days': 222,
        'weekly_hours': '14.5',
      });
      expect(s.phases, hasLength(1), reason: 'nameless phases are dropped');
      expect(s.phases.single.name(bangla: false), 'Foundation');
      expect(s.phases.single.focus(bangla: false), 'মূল বিষয়', reason: 'focus falls back to Bangla');
      expect(s.phases.single.isCurrent(DateTime.utc(2026, 11)), isTrue);
      expect(s.milestones.map((m) => m.titleBn), ['প্রথম', 'দ্বিতীয়', 'তারিখহীন']);
      expect(s.totalDays, 222);
      expect(s.weeklyHours, 14.5);
    });

    test('garbage summary → empty', () {
      expect(PlanSummary.parse(null).isEmpty, isTrue);
      expect(PlanSummary.parse('[]').isEmpty, isTrue);
      expect(PlanSummary.parse(const {'phases': 'nope'}).isEmpty, isTrue);
      expect(PlanSummary.parse('{"phases":[{"name_bn":"ক"}]}').phases, hasLength(1));
    });

    test('tips accept strings and objects', () {
      expect(
        parseAiTips([
          '  a ',
          '',
          5,
          {'text': 'b'},
          {'tip_bn': 'c'},
          {'x': 'y'},
        ]),
        ['a', 'b', 'c'],
      );
      expect(parseAiTips(null), isEmpty);
    });
  });

  group('PlanOverview', () {
    test('no plan', () {
      expect(PlanOverview.fromJson(const {'has_plan': false}).hasPlan, isFalse);
    });

    test('aggregates and recent days', () {
      final o = PlanOverview.fromJson(const {
        'has_plan': true,
        'id': 'p',
        'exam_date': '2027-05-14',
        'total_days': 200,
        'done_days': 50,
        'partial_days': 5,
        'missed_days': 3,
        'locked_days': 140,
        'days_left': 222,
        'kinds': {'study': 120, 'revision': '40', 'rest': null},
        'summary': <String, Object>{},
        'ai_tips': ['নিয়মিত পড়ুন'],
        'recent': [
          {'id': 2, 'day_date': '2026-10-05', 'kind': 'study', 'title_bn': 'খ', 'status': 'pending'},
          {
            'id': 1,
            'day_date': '2026-10-04',
            'kind': 'study',
            'title_bn': 'ক',
            'status': 'done',
            'completed_items': 3,
            'total_items': 3,
          },
        ],
      });
      expect(o.completion, 0.25);
      expect(o.kinds, {'study': 120, 'revision': 40});
      expect(o.recent.map((d) => d.id), [1, 2], reason: 'sorted by date');
      expect(o.recent.first.progress, 1);
      expect(o.aiTips.single, 'নিয়মিত পড়ুন');
      final cached = PlanOverview.fromJson(o.toJson());
      expect(cached.lockedDays, 140);
      expect(cached.recent, hasLength(2));
    });
  });
}
