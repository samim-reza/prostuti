import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/study_plan/application/plan_exam.dart';
import 'package:prostuti/features/study_plan/data/plan_models.dart';

void main() {
  const examItem = PlanItem(key: 'e1', type: PlanItemType.exam, titleBn: 'পরীক্ষা');

  group('planExamLaunch', () {
    test('topic item → topic exam linked to the plan', () {
      final l = planExamLaunch(
        dayId: 5,
        dayKind: PlanDayKind.study,
        item: const PlanItem(key: 'e1', type: PlanItemType.exam, titleBn: 'x', topicId: 102, count: 300),
      );
      expect(l.kind, ExamKind.topic);
      expect(l.config, {'topic_id': 102, 'count': 100, 'plan_day_id': 5, 'plan_item_key': 'e1'});
    });

    test('model test day → model test with size snapped to an allowed value', () {
      final l = planExamLaunch(
        dayId: 6,
        dayKind: PlanDayKind.modelTest,
        item: const PlanItem(key: 'm', type: PlanItemType.exam, titleBn: 'x', count: 60),
      );
      expect(l.kind, ExamKind.modelTest);
      expect(l.config['size'], 50);
      expect(l.config['plan_day_id'], 6);
    });

    test('subject item → subject exam', () {
      final l = planExamLaunch(
        dayId: 1,
        dayKind: PlanDayKind.revision,
        item: const PlanItem(key: 's', type: PlanItemType.exam, titleBn: 'x', subjectId: 3),
      );
      expect(l.kind, ExamKind.subject);
      expect(l.config['subject_id'], 3);
      expect(l.config['count'], 20);
    });

    test('otherwise → weak-topic exam (free days)', () {
      final l = planExamLaunch(dayId: 9, dayKind: PlanDayKind.weakTopicExam, item: examItem);
      expect(l.kind, ExamKind.weakTopic);
      expect(l.config, {'count': 20, 'plan_day_id': 9, 'plan_item_key': 'e1'});
    });

    test('items without a key are still linked to the day', () {
      final l = planExamLaunch(
        dayId: 9,
        dayKind: PlanDayKind.weakTopicExam,
        item: const PlanItem(key: '', type: PlanItemType.exam, titleBn: 'x'),
      );
      expect(l.config.containsKey('plan_item_key'), isFalse);
      expect(l.config['plan_day_id'], 9);
    });
  });

  test('weakTopicDayLaunch picks the first unfinished exam item', () {
    final day = PlanDay(
      id: 4,
      date: DateTime.utc(2026, 10, 4),
      kind: PlanDayKind.weakTopicExam,
      titleBn: 'দিন',
      items: const [
        PlanItem(key: 'done', type: PlanItemType.exam, titleBn: 'a', done: true),
        PlanItem(key: 'r', type: PlanItemType.read, titleBn: 'b'),
        PlanItem(key: 'next', type: PlanItemType.exam, titleBn: 'c', count: 30),
      ],
    );
    final l = weakTopicDayLaunch(day);
    expect(l.kind, ExamKind.weakTopic);
    expect(l.config, {'plan_day_id': 4, 'plan_item_key': 'next', 'count': 30});
  });

  test('practiceRouteFor prefers topic, then subject, then the question bank', () {
    expect(
      practiceRouteFor(const PlanItem(key: 'a', type: PlanItemType.read, titleBn: 'x', topicId: 7, subjectId: 1)),
      Routes.practice(topicId: 7),
    );
    expect(
      practiceRouteFor(const PlanItem(key: 'a', type: PlanItemType.read, titleBn: 'x', subjectId: 1)),
      Routes.practice(subjectId: 1),
    );
    expect(practiceRouteFor(const PlanItem(key: 'a', type: PlanItemType.read, titleBn: 'x')), Routes.questionBank);
  });
}
