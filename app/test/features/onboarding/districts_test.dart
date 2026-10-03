import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/features/onboarding/data/districts.dart';

void main() {
  test('exactly 64 unique districts in 8 divisions', () {
    expect(bangladeshDistricts, hasLength(64));
    expect(bangladeshDistricts.map((d) => d.nameBn).toSet(), hasLength(64));
    expect(bangladeshDistricts.map((d) => d.nameEn.toLowerCase()).toSet(), hasLength(64));
    final perDivision = <String, int>{};
    for (final d in bangladeshDistricts) {
      perDivision[d.division] = (perDivision[d.division] ?? 0) + 1;
    }
    expect(perDivision, {
      'dhaka': 13,
      'chattogram': 11,
      'rajshahi': 8,
      'khulna': 10,
      'barishal': 6,
      'sylhet': 4,
      'rangpur': 8,
      'mymensingh': 4,
    });
  });

  test('every Bangla name is in Bangla script', () {
    final bangla = RegExp(r'^[ঀ-৿\s]+$');
    for (final d in bangladeshDistricts) {
      expect(bangla.hasMatch(d.nameBn), isTrue, reason: d.nameBn);
    }
  });

  test('search matches Bangla and English, case-insensitively', () {
    List<String> search(String q) => bangladeshDistricts.where((d) => d.matches(q)).map((d) => d.nameEn).toList();
    expect(search('ঢাকা'), ['Dhaka']);
    expect(search('dhaka'), ['Dhaka']);
    expect(search('SYL'), ['Sylhet']);
    expect(search(''), hasLength(64));
    expect(search('zzz'), isEmpty);
  });

  test('search tolerates both encodings of য়/ড়', () {
    // "বগুড়া" typed with ড + nukta instead of the precomposed ড়.
    const decomposed = 'বগুড়া';
    expect(bangladeshDistricts.where((d) => d.matches(decomposed)).single.nameEn, 'Bogura');
    expect(District.find(decomposed)?.nameEn, 'Bogura');
  });

  test('find resolves stored values in either language', () {
    expect(District.find('চট্টগ্রাম')?.nameEn, 'Chattogram');
    expect(District.find('chattogram')?.nameBn, 'চট্টগ্রাম');
    expect(District.find(null), isNull);
    expect(District.find('Atlantis'), isNull);
  });
}
