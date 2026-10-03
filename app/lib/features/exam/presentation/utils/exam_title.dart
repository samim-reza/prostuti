import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';

const _customDefaultTitle = 'অনুশীলন পরীক্ষা';

/// `start_exam` stores Bangla titles ("মডেল টেস্ট · 100 নম্বর",
/// "বিষয়ভিত্তিক পরীক্ষা · কম্পিউটার ও তথ্যপ্রযুক্তি" …). This rebuilds the
/// title in the UI language from its known shape, translating subject and
/// topic names via the catalog. Unknown shapes (daily exam, previous-year
/// source names, user titles) are kept, with Bangla digits in Bangla UI.
String localizeExamTitle(
  String title,
  ExamKind kind, {
  required AppLocalizations l,
  required bool bangla,
  List<Subject> subjects = const [],
}) {
  String digits(String s) => Fmt.digits(s, bangla: bangla);
  final sep = title.indexOf(' · ');
  final suffix = sep < 0 ? null : title.substring(sep + 3).trim();

  switch (kind) {
    case ExamKind.modelTest:
      final marks = RegExp(r'\d+').firstMatch(suffix ?? title)?.group(0);
      if (marks != null) return l.examTitleModelTest(digits(marks));
    case ExamKind.subject:
      if (suffix != null) {
        for (final s in subjects) {
          if (s.nameBn == suffix) return l.examTitleSubject(bangla ? s.nameBn : s.nameEn);
        }
        return l.examTitleSubject(suffix);
      }
    case ExamKind.topic:
      if (suffix != null) {
        for (final s in subjects) {
          for (final t in s.topics) {
            if (t.nameBn == suffix) return l.examTitleTopic(bangla ? t.nameBn : t.nameEn);
          }
        }
        return l.examTitleTopic(suffix);
      }
    case ExamKind.weakTopic:
      return l.examTitleWeak;
    case ExamKind.placement:
      return l.examTitlePlacement;
    case ExamKind.custom:
      if (title.trim().isEmpty || title == _customDefaultTitle) return l.examTitleCustom;
    case ExamKind.daily:
    case ExamKind.previousYear:
      break;
  }
  return digits(title);
}

/// Widget-side convenience: localizes with the cached subject catalog.
String examTitleOf(BuildContext context, WidgetRef ref, String title, ExamKind kind) => localizeExamTitle(
  title,
  kind,
  l: context.l10n,
  bangla: context.isBn,
  subjects: ref.watch(subjectsProvider).value ?? const [],
);
