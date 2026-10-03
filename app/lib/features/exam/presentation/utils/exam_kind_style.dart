import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';

/// Icon, accent colour and label for each exam kind.
extension ExamKindStyle on ExamKind {
  IconData get icon => switch (this) {
    ExamKind.placement => Icons.insights_rounded,
    ExamKind.modelTest => Icons.assignment_rounded,
    ExamKind.daily => Icons.newspaper_rounded,
    ExamKind.subject => Icons.menu_book_rounded,
    ExamKind.topic => Icons.topic_rounded,
    ExamKind.weakTopic => Icons.track_changes_rounded,
    ExamKind.previousYear => Icons.history_edu_rounded,
    ExamKind.custom => Icons.tune_rounded,
  };

  Color get accent => switch (this) {
    ExamKind.placement => AppColors.info,
    ExamKind.modelTest => const Color(0xFF3559E0),
    ExamKind.daily => AppColors.brand,
    ExamKind.subject => const Color(0xFF0E7C66),
    ExamKind.topic => const Color(0xFF1F8FB3),
    ExamKind.weakTopic => const Color(0xFF7A4BD6),
    ExamKind.previousYear => const Color(0xFFD9480F),
    ExamKind.custom => const Color(0xFF5C7CFA),
  };

  String label(BuildContext context) {
    final l = context.l10n;
    return switch (this) {
      ExamKind.placement => l.examKindPlacement,
      ExamKind.modelTest => l.examKindModelTest,
      ExamKind.daily => l.examKindDaily,
      ExamKind.subject => l.examKindSubject,
      ExamKind.topic => l.examKindTopic,
      ExamKind.weakTopic => l.examKindWeakTopic,
      ExamKind.previousYear => l.examKindPreviousYear,
      ExamKind.custom => l.examKindCustom,
    };
  }
}

/// Score colour: green ≥ 60 %, amber ≥ 40 %, red below.
Color scoreColor(double percent) {
  if (percent >= 60) return AppColors.success;
  if (percent >= 40) return AppColors.warning;
  return AppColors.danger;
}
