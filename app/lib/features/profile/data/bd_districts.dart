/// The 64 districts of Bangladesh as (Bangla, English) pairs, grouped by
/// division. `profiles.district` stores the Bangla name; lookups accept
/// either spelling so older/English values still display correctly.
const bdDistricts = <(String, String)>[
  // Dhaka division
  ('ঢাকা', 'Dhaka'),
  ('গাজীপুর', 'Gazipur'),
  ('নারায়ণগঞ্জ', 'Narayanganj'),
  ('নরসিংদী', 'Narsingdi'),
  ('মুন্সিগঞ্জ', 'Munshiganj'),
  ('মানিকগঞ্জ', 'Manikganj'),
  ('টাঙ্গাইল', 'Tangail'),
  ('কিশোরগঞ্জ', 'Kishoreganj'),
  ('ফরিদপুর', 'Faridpur'),
  ('গোপালগঞ্জ', 'Gopalganj'),
  ('মাদারীপুর', 'Madaripur'),
  ('রাজবাড়ী', 'Rajbari'),
  ('শরীয়তপুর', 'Shariatpur'),
  // Chattogram division
  ('চট্টগ্রাম', 'Chattogram'),
  ('কক্সবাজার', "Cox's Bazar"),
  ('কুমিল্লা', 'Cumilla'),
  ('ব্রাহ্মণবাড়িয়া', 'Brahmanbaria'),
  ('চাঁদপুর', 'Chandpur'),
  ('ফেনী', 'Feni'),
  ('নোয়াখালী', 'Noakhali'),
  ('লক্ষ্মীপুর', 'Lakshmipur'),
  ('রাঙ্গামাটি', 'Rangamati'),
  ('খাগড়াছড়ি', 'Khagrachhari'),
  ('বান্দরবান', 'Bandarban'),
  // Rajshahi division
  ('রাজশাহী', 'Rajshahi'),
  ('বগুড়া', 'Bogura'),
  ('পাবনা', 'Pabna'),
  ('সিরাজগঞ্জ', 'Sirajganj'),
  ('নাটোর', 'Natore'),
  ('নওগাঁ', 'Naogaon'),
  ('চাঁপাইনবাবগঞ্জ', 'Chapai Nawabganj'),
  ('জয়পুরহাট', 'Joypurhat'),
  // Khulna division
  ('খুলনা', 'Khulna'),
  ('যশোর', 'Jashore'),
  ('সাতক্ষীরা', 'Satkhira'),
  ('বাগেরহাট', 'Bagerhat'),
  ('কুষ্টিয়া', 'Kushtia'),
  ('ঝিনাইদহ', 'Jhenaidah'),
  ('মাগুরা', 'Magura'),
  ('নড়াইল', 'Narail'),
  ('চুয়াডাঙ্গা', 'Chuadanga'),
  ('মেহেরপুর', 'Meherpur'),
  // Barishal division
  ('বরিশাল', 'Barishal'),
  ('পটুয়াখালী', 'Patuakhali'),
  ('ভোলা', 'Bhola'),
  ('পিরোজপুর', 'Pirojpur'),
  ('বরগুনা', 'Barguna'),
  ('ঝালকাঠি', 'Jhalokati'),
  // Sylhet division
  ('সিলেট', 'Sylhet'),
  ('মৌলভীবাজার', 'Moulvibazar'),
  ('হবিগঞ্জ', 'Habiganj'),
  ('সুনামগঞ্জ', 'Sunamganj'),
  // Rangpur division
  ('রংপুর', 'Rangpur'),
  ('দিনাজপুর', 'Dinajpur'),
  ('গাইবান্ধা', 'Gaibandha'),
  ('কুড়িগ্রাম', 'Kurigram'),
  ('লালমনিরহাট', 'Lalmonirhat'),
  ('নীলফামারী', 'Nilphamari'),
  ('পঞ্চগড়', 'Panchagarh'),
  ('ঠাকুরগাঁও', 'Thakurgaon'),
  // Mymensingh division
  ('ময়মনসিংহ', 'Mymensingh'),
  ('জামালপুর', 'Jamalpur'),
  ('নেত্রকোণা', 'Netrokona'),
  ('শেরপুর', 'Sherpur'),
];

/// Finds the district whose Bangla or English name matches [value]
/// (case-insensitive). Returns null for unknown values.
(String, String)? findDistrict(String? value) {
  final v = value?.trim().toLowerCase();
  if (v == null || v.isEmpty) return null;
  for (final d in bdDistricts) {
    if (d.$1 == v || d.$2.toLowerCase() == v) return d;
  }
  return null;
}

/// Localized district name; unknown values are shown as stored.
String? districtLabel(String? value, {required bool bangla}) {
  final d = findDistrict(value);
  if (d == null) return (value == null || value.trim().isEmpty) ? null : value.trim();
  return bangla ? d.$1 : d.$2;
}

/// Districts whose name (either language) contains [query].
List<(String, String)> searchDistricts(String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return bdDistricts;
  return [
    for (final d in bdDistricts)
      if (d.$1.contains(q) || d.$2.toLowerCase().contains(q)) d,
  ];
}
