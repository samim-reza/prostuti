import 'package:flutter/widgets.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/utils/json.dart';

/// One `public.exam_tracks` row: a section of the question bank and model
/// tests whose question pattern differs (BCS, bank jobs, other govt jobs).
/// A question belongs to a track when its `exam_tags` contain [code].
@immutable
class ExamTrack {
  const ExamTrack({
    required this.code,
    required this.nameBn,
    required this.nameEn,
    required this.sizes,
    required this.fullMarks,
    required this.negativeMark,
    required this.secondsPerQuestion,
    required this.distribution,
    this.descriptionBn,
    this.descriptionEn,
    this.sort = 0,
  });

  factory ExamTrack.fromJson(Map<String, dynamic> j) => ExamTrack(
    code: j.str('code'),
    nameBn: j.str('name_bn'),
    nameEn: j.str('name_en', j.str('name_bn')),
    descriptionBn: j.strOrNull('description_bn'),
    descriptionEn: j.strOrNull('description_en'),
    sizes: [for (final v in (j['sizes'] as List?) ?? const []) ?int.tryParse('$v')],
    fullMarks: j.integer('full_marks', 100),
    negativeMark: j.dbl('negative_mark'),
    secondsPerQuestion: j.integer('seconds_per_question', 36),
    distribution: {
      for (final e in j.obj('distribution').entries)
        if (int.tryParse('${e.value}') case final n? when n > 0) e.key: n,
    },
    sort: j.integer('sort'),
  );

  static const columns =
      'code, name_bn, name_en, description_bn, description_en, sizes, full_marks, negative_mark, '
      'seconds_per_question, distribution, sort';

  static const bcs = 'bcs';
  static const bank = 'bank';
  static const govt = 'govt';

  /// Mirrors the 0016 migration, so the sections work before the first
  /// fetch (fresh install while offline).
  static const defaults = [
    ExamTrack(
      code: bcs,
      nameBn: 'বিসিএস',
      nameEn: 'BCS',
      sizes: [25, 50, 100, 200],
      fullMarks: 200,
      negativeMark: 0.5,
      secondsPerQuestion: 36,
      distribution: {
        'bangla': 30,
        'english': 30,
        'bd_affairs': 25,
        'international': 25,
        'geography': 10,
        'science': 15,
        'computer': 15,
        'math': 20,
        'mental_ability': 15,
        'ethics': 15,
      },
      sort: 1,
    ),
    ExamTrack(
      code: bank,
      nameBn: 'ব্যাংক',
      nameEn: 'Bank jobs',
      sizes: [25, 50, 80, 100],
      fullMarks: 100,
      negativeMark: 0.25,
      secondsPerQuestion: 45,
      distribution: {
        'bangla': 15,
        'english': 30,
        'math': 20,
        'mental_ability': 5,
        'bd_affairs': 10,
        'international': 10,
        'computer': 10,
      },
      sort: 2,
    ),
    ExamTrack(
      code: govt,
      nameBn: 'অন্যান্য চাকরি',
      nameEn: 'Other jobs',
      sizes: [25, 50, 80, 100],
      fullMarks: 100,
      negativeMark: 0.25,
      secondsPerQuestion: 45,
      distribution: {
        'bangla': 25,
        'english': 25,
        'math': 25,
        'bd_affairs': 10,
        'international': 5,
        'science': 5,
        'computer': 5,
      },
      sort: 3,
    ),
  ];

  /// The track matching a learner's target exams (first match wins).
  static String forTargetExams(List<String> targets) {
    for (final t in targets) {
      switch (t) {
        case 'bcs':
          return bcs;
        case 'bank':
          return bank;
        case 'primary' || 'ntrca' || 'govt':
          return govt;
      }
    }
    return bcs;
  }

  final String code;
  final String nameBn;
  final String nameEn;
  final String? descriptionBn;
  final String? descriptionEn;
  final List<int> sizes;
  final int fullMarks;
  final double negativeMark;
  final int secondsPerQuestion;

  /// Subject code → marks out of [fullMarks].
  final Map<String, int> distribution;
  final int sort;

  String name(BuildContext context) => context.isBn ? nameBn : nameEn;

  String? description(BuildContext context) => context.isBn ? descriptionBn : (descriptionEn ?? descriptionBn);

  Map<String, dynamic> toJson() => {
    'code': code,
    'name_bn': nameBn,
    'name_en': nameEn,
    'description_bn': descriptionBn,
    'description_en': descriptionEn,
    'sizes': sizes,
    'full_marks': fullMarks,
    'negative_mark': negativeMark,
    'seconds_per_question': secondsPerQuestion,
    'distribution': distribution,
    'sort': sort,
  };
}
