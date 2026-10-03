import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:prostuti/features/exam/application/model_test_plan.dart';

Subject _s(int id, int marks) => Subject(id: id, code: 's$id', nameBn: 'বিষয় $id', nameEn: 'S$id', bcsMarks: marks);

void main() {
  // BCS preliminary syllabus (200 marks), in `sort` order.
  final bcs = [
    for (final (i, m) in [30, 30, 25, 25, 10, 15, 15, 20, 15, 15].indexed) _s(i + 1, m),
  ];

  test('200 marks maps 1:1 to BCS marks and 120 minutes', () {
    final shares = ModelTestPlan.distribution(bcs, 200);
    expect(shares.map((s) => s.count), [30, 30, 25, 25, 10, 15, 15, 20, 15, 15]);
    expect(ModelTestPlan.totalQuestions(shares), 200);
    expect(ModelTestPlan.duration(200, shares: shares), const Duration(minutes: 120));
  });

  test('smaller tests use largest remainder (ties by sort), like start_exam', () {
    final shares = ModelTestPlan.distribution(bcs, 25);
    expect(shares.map((s) => s.count), [4, 4, 3, 3, 1, 2, 2, 2, 2, 2]);
    expect(ModelTestPlan.totalQuestions(shares), 25);
    expect(ModelTestPlan.duration(25, shares: shares), const Duration(minutes: 15));
  });

  test('matches the server for 50 and 100 marks', () {
    expect(ModelTestPlan.distribution(bcs, 50).map((s) => s.count), [8, 7, 6, 6, 2, 4, 4, 5, 4, 4]);
    expect(ModelTestPlan.distribution(bcs, 100).map((s) => s.count), [15, 15, 13, 13, 5, 8, 7, 10, 7, 7]);
  });

  test('every size yields exactly that many questions', () {
    for (final size in ModelTestPlan.sizes) {
      expect(ModelTestPlan.totalQuestions(ModelTestPlan.distribution(bcs, size)), size, reason: '$size');
    }
  });

  test('subjects without BCS marks are excluded', () {
    expect(ModelTestPlan.distribution([_s(1, 0), _s(2, 30)], 100).map((s) => s.subject.id), [2]);
  });

  test('falls back to size × 36 s before subjects load', () {
    expect(ModelTestPlan.duration(50), const Duration(minutes: 30));
  });
}
