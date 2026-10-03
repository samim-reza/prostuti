import 'package:flutter/foundation.dart';

/// A district of Bangladesh. `profiles.district` stores the Bangla name
/// (canonical); [find] resolves either spelling for display.
@immutable
class District {
  const District(this.nameBn, this.nameEn, this.division);

  final String nameBn;
  final String nameEn;
  final String division;

  String name({required bool bangla}) => bangla ? nameBn : nameEn;

  /// Case-insensitive match on the Bangla or English name. Bangla is
  /// normalised so both keyboard encodings of ড়/ঢ়/য় match.
  bool matches(String query) {
    final q = normalizeBangla(query.trim().toLowerCase());
    if (q.isEmpty) return true;
    return normalizeBangla(nameBn).contains(q) || nameEn.toLowerCase().contains(q);
  }

  static District? find(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final v = value.trim().toLowerCase();
    for (final d in bangladeshDistricts) {
      if (normalizeBangla(d.nameBn) == normalizeBangla(value.trim()) || d.nameEn.toLowerCase() == v) return d;
    }
    return null;
  }
}

/// Decomposes the precomposed nukta letters (U+09DC/09DD/09DF) that
/// different Bangla keyboards produce differently.
String normalizeBangla(String s) =>
    s.replaceAll('\u09DC', '\u09A1\u09BC').replaceAll('\u09DD', '\u09A2\u09BC').replaceAll('\u09DF', '\u09AF\u09BC');

/// All 64 districts, grouped by division (alphabetical within a division).
const bangladeshDistricts = <District>[
  // Dhaka
  District('ঢাকা', 'Dhaka', 'dhaka'),
  District('ফরিদপুর', 'Faridpur', 'dhaka'),
  District('গাজীপুর', 'Gazipur', 'dhaka'),
  District('গোপালগঞ্জ', 'Gopalganj', 'dhaka'),
  District('কিশোরগঞ্জ', 'Kishoreganj', 'dhaka'),
  District('মাদারীপুর', 'Madaripur', 'dhaka'),
  District('মানিকগঞ্জ', 'Manikganj', 'dhaka'),
  District('মুন্সীগঞ্জ', 'Munshiganj', 'dhaka'),
  District('নারায়ণগঞ্জ', 'Narayanganj', 'dhaka'),
  District('নরসিংদী', 'Narsingdi', 'dhaka'),
  District('রাজবাড়ী', 'Rajbari', 'dhaka'),
  District('শরীয়তপুর', 'Shariatpur', 'dhaka'),
  District('টাঙ্গাইল', 'Tangail', 'dhaka'),
  // Chattogram
  District('বান্দরবান', 'Bandarban', 'chattogram'),
  District('ব্রাহ্মণবাড়িয়া', 'Brahmanbaria', 'chattogram'),
  District('চাঁদপুর', 'Chandpur', 'chattogram'),
  District('চট্টগ্রাম', 'Chattogram', 'chattogram'),
  District('কুমিল্লা', 'Cumilla', 'chattogram'),
  District('কক্সবাজার', "Cox's Bazar", 'chattogram'),
  District('ফেনী', 'Feni', 'chattogram'),
  District('খাগড়াছড়ি', 'Khagrachhari', 'chattogram'),
  District('লক্ষ্মীপুর', 'Lakshmipur', 'chattogram'),
  District('নোয়াখালী', 'Noakhali', 'chattogram'),
  District('রাঙ্গামাটি', 'Rangamati', 'chattogram'),
  // Rajshahi
  District('বগুড়া', 'Bogura', 'rajshahi'),
  District('চাঁপাইনবাবগঞ্জ', 'Chapainawabganj', 'rajshahi'),
  District('জয়পুরহাট', 'Joypurhat', 'rajshahi'),
  District('নওগাঁ', 'Naogaon', 'rajshahi'),
  District('নাটোর', 'Natore', 'rajshahi'),
  District('পাবনা', 'Pabna', 'rajshahi'),
  District('রাজশাহী', 'Rajshahi', 'rajshahi'),
  District('সিরাজগঞ্জ', 'Sirajganj', 'rajshahi'),
  // Khulna
  District('বাগেরহাট', 'Bagerhat', 'khulna'),
  District('চুয়াডাঙ্গা', 'Chuadanga', 'khulna'),
  District('যশোর', 'Jashore', 'khulna'),
  District('ঝিনাইদহ', 'Jhenaidah', 'khulna'),
  District('খুলনা', 'Khulna', 'khulna'),
  District('কুষ্টিয়া', 'Kushtia', 'khulna'),
  District('মাগুরা', 'Magura', 'khulna'),
  District('মেহেরপুর', 'Meherpur', 'khulna'),
  District('নড়াইল', 'Narail', 'khulna'),
  District('সাতক্ষীরা', 'Satkhira', 'khulna'),
  // Barishal
  District('বরগুনা', 'Barguna', 'barishal'),
  District('বরিশাল', 'Barishal', 'barishal'),
  District('ভোলা', 'Bhola', 'barishal'),
  District('ঝালকাঠি', 'Jhalokati', 'barishal'),
  District('পটুয়াখালী', 'Patuakhali', 'barishal'),
  District('পিরোজপুর', 'Pirojpur', 'barishal'),
  // Sylhet
  District('হবিগঞ্জ', 'Habiganj', 'sylhet'),
  District('মৌলভীবাজার', 'Moulvibazar', 'sylhet'),
  District('সুনামগঞ্জ', 'Sunamganj', 'sylhet'),
  District('সিলেট', 'Sylhet', 'sylhet'),
  // Rangpur
  District('দিনাজপুর', 'Dinajpur', 'rangpur'),
  District('গাইবান্ধা', 'Gaibandha', 'rangpur'),
  District('কুড়িগ্রাম', 'Kurigram', 'rangpur'),
  District('লালমনিরহাট', 'Lalmonirhat', 'rangpur'),
  District('নীলফামারী', 'Nilphamari', 'rangpur'),
  District('পঞ্চগড়', 'Panchagarh', 'rangpur'),
  District('রংপুর', 'Rangpur', 'rangpur'),
  District('ঠাকুরগাঁও', 'Thakurgaon', 'rangpur'),
  // Mymensingh
  District('জামালপুর', 'Jamalpur', 'mymensingh'),
  District('ময়মনসিংহ', 'Mymensingh', 'mymensingh'),
  District('নেত্রকোনা', 'Netrokona', 'mymensingh'),
  District('শেরপুর', 'Sherpur', 'mymensingh'),
];
