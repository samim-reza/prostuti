import 'package:flutter/foundation.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/study_plan/data/plan_models.dart';

/// Which exam to start for a routine item, with the config that links the
/// session back to the plan (`plan_day_id` / `plan_item_key`), so submitting
/// the exam ticks the item off server-side.
@immutable
class PlanExamLaunch {
  const PlanExamLaunch(this.kind, this.config);

  final ExamKind kind;
  final Map<String, dynamic> config;
}

const _modelTestSizes = [25, 50, 100, 200];

/// Pure mapping (unit tested):
/// * model-test days without a topic/subject → full model test (size snapped
///   to 25/50/100/200);
/// * a topic → topic exam; a subject → subject exam;
/// * otherwise → weak-topic exam (free days are used for weak topics).
PlanExamLaunch planExamLaunch({required int dayId, required PlanDayKind dayKind, required PlanItem item}) {
  final link = <String, dynamic>{'plan_day_id': dayId, if (item.key.isNotEmpty) 'plan_item_key': item.key};
  final count = (item.count ?? 20).clamp(5, 100);

  if (item.topicId != null) {
    return PlanExamLaunch(ExamKind.topic, {'topic_id': item.topicId, 'count': count, ...link});
  }
  if (dayKind == PlanDayKind.modelTest) {
    final wanted = item.count ?? 100;
    final size = _modelTestSizes.reduce((a, b) => (a - wanted).abs() <= (b - wanted).abs() ? a : b);
    return PlanExamLaunch(ExamKind.modelTest, {'size': size, ...link});
  }
  if (item.subjectId != null) {
    return PlanExamLaunch(ExamKind.subject, {'subject_id': item.subjectId, 'count': count, ...link});
  }
  return PlanExamLaunch(ExamKind.weakTopic, {'count': count, ...link});
}

/// The weak-topic exam of a `weak_topic_exam` day (Home's big button):
/// linked to the first unfinished exam item when there is one.
PlanExamLaunch weakTopicDayLaunch(PlanDay day) {
  PlanItem? examItem;
  for (final i in day.items) {
    if (i.type == PlanItemType.exam && !i.done) {
      examItem = i;
      break;
    }
  }
  return PlanExamLaunch(ExamKind.weakTopic, {
    'plan_day_id': day.id,
    if (examItem != null && examItem.key.isNotEmpty) 'plan_item_key': examItem.key,
    'count': (examItem?.count ?? 20).clamp(5, 100),
  });
}

/// Route for reading / practising an item (topic → subject → question bank).
String practiceRouteFor(PlanItem item) {
  if (item.topicId != null) return Routes.practice(topicId: item.topicId);
  if (item.subjectId != null) return Routes.practice(subjectId: item.subjectId);
  return Routes.questionBank;
}
