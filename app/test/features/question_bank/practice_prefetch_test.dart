import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/features/question_bank/application/practice_controller.dart';

void main() {
  bool should(int index, int loaded, {bool hasMore = true, bool busy = false}) =>
      PracticePrefetch.shouldPrefetch(index: index, loaded: loaded, hasMore: hasMore, busy: busy);

  test('prefetches when 3 questions remain after the current one', () {
    expect(should(15, 20), isFalse, reason: '4 remain');
    expect(should(16, 20), isTrue, reason: '3 remain');
    expect(should(19, 20), isTrue, reason: 'last question');
    expect(should(20, 20), isTrue, reason: 'end page');
  });

  test('never while busy or after the last page', () {
    expect(should(18, 20, busy: true), isFalse);
    expect(should(18, 20, hasMore: false), isFalse);
  });

  test('a short first page prefetches immediately', () {
    expect(should(0, 3), isTrue);
    expect(should(0, 0), isTrue);
  });

  test('custom threshold', () {
    expect(PracticePrefetch.shouldPrefetch(index: 10, loaded: 20, hasMore: true, busy: false, threshold: 9), isTrue);
  });
}
