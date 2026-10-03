import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/exam/presentation/utils/exam_title.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final bn = lookupAppLocalizations(const Locale('bn'));
  const subjects = [
    Subject(
      id: 7,
      code: 'computer',
      nameBn: 'কম্পিউটার ও তথ্যপ্রযুক্তি',
      nameEn: 'Computer & ICT',
      bcsMarks: 15,
      topics: [Topic(id: 704, code: 'net', nameBn: 'নেটওয়ার্ক', nameEn: 'Networking')],
    ),
  ];

  String t(String title, ExamKind kind, {bool bangla = false}) =>
      localizeExamTitle(title, kind, l: bangla ? bn : en, bangla: bangla, subjects: subjects);

  test('model test titles are rebuilt in the UI language', () {
    expect(t('মডেল টেস্ট · 100 নম্বর', ExamKind.modelTest), 'Model test · 100 marks');
    expect(t('মডেল টেস্ট · 100 নম্বর', ExamKind.modelTest, bangla: true), 'মডেল টেস্ট · ১০০ নম্বর');
  });

  test('subject and topic names are translated via the catalog', () {
    expect(t('বিষয়ভিত্তিক পরীক্ষা · কম্পিউটার ও তথ্যপ্রযুক্তি', ExamKind.subject), 'Subject exam · Computer & ICT');
    expect(t('টপিকভিত্তিক পরীক্ষা · নেটওয়ার্ক', ExamKind.topic), 'Topic exam · Networking');
    expect(t('বিষয়ভিত্তিক পরীক্ষা · অজানা', ExamKind.subject), 'Subject exam · অজানা');
  });

  test('fixed titles', () {
    expect(t('দুর্বল টপিক পরীক্ষা', ExamKind.weakTopic), 'Weak-topic exam');
    expect(t('লেভেল নির্ধারণী পরীক্ষা', ExamKind.placement), 'Level test');
    expect(t('অনুশীলন পরীক্ষা', ExamKind.custom), 'Practice exam');
  });

  test('custom user titles and source names are kept', () {
    expect(t('আমার পরীক্ষা', ExamKind.custom), 'আমার পরীক্ষা');
    expect(t('৪৫তম বিসিএস 2023', ExamKind.previousYear), '৪৫তম বিসিএস 2023');
    expect(t('৪৫তম বিসিএস 2023', ExamKind.previousYear, bangla: true), '৪৫তম বিসিএস ২০২৩');
  });
}
