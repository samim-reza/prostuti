import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:prostuti/features/exam/application/exam_clock.dart';

@immutable
class SubjectShare {
  const SubjectShare(this.subject, this.count);
  final Subject subject;
  final int count;
}

/// Mirrors `start_exam('model_test')`: every BCS subject contributes
/// `max(1, round(bcs_marks × size / 200))` questions and the timer runs at
/// 36 s per question (200 questions → 120 minutes).
abstract final class ModelTestPlan {
  static const sizes = [25, 50, 100, 200];
  static const fullMarks = 200;

  static List<SubjectShare> distribution(List<Subject> subjects, int size) => [
    for (final s in subjects)
      if (s.bcsMarks > 0) SubjectShare(s, math.max(1, (s.bcsMarks * size / fullMarks).round())),
  ];

  static int totalQuestions(List<SubjectShare> shares) => shares.fold(0, (sum, s) => sum + s.count);

  /// Exam duration; falls back to `size × 36 s` while subjects are loading.
  static Duration duration(int size, {List<SubjectShare>? shares}) {
    final count = (shares == null || shares.isEmpty) ? size : totalQuestions(shares);
    return ExamTiming.forQuestions(count, withMinimum: false);
  }
}
