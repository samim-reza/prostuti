import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/features/exam/presentation/utils/option_labels.dart';

void main() {
  test('Bangla questions use ক খ গ ঘ', () {
    expect([for (var i = 0; i < 4; i++) optionLabel(i, language: 'bn')], ['ক', 'খ', 'গ', 'ঘ']);
    expect(optionLabel(4, language: 'bn'), 'ঙ');
  });

  test('English questions use A B C D', () {
    expect([for (var i = 0; i < 4; i++) optionLabel(i, language: 'en')], ['A', 'B', 'C', 'D']);
  });

  test('unknown languages fall back to Bangla labels', () {
    expect(optionLabel(1, language: 'xx'), 'খ');
  });

  test('out-of-range indexes fall back to numbers', () {
    expect(optionLabel(9, language: 'en'), '10');
    expect(optionLabel(-1, language: 'bn'), '0');
  });
}
