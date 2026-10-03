import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/core/cache/cache_store.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:prostuti/features/question_bank/data/offline_pack_store.dart';
import 'package:prostuti/features/question_bank/data/question_bank_repository.dart';
import 'package:prostuti/features/study/presentation/screens/study_screen.dart';

void main() {
  const subjects = [
    Subject(id: 1, code: 'bangla', nameBn: 'বাংলা ভাষা ও সাহিত্য', nameEn: 'Bangla', bcsMarks: 30, mastery: 0.42),
    Subject(id: 7, code: 'computer', nameBn: 'কম্পিউটার ও তথ্যপ্রযুক্তি', nameEn: 'Computer & ICT', bcsMarks: 15),
  ];

  Future<void> pump(WidgetTester tester, Locale locale) async {
    final cache = await CacheStore.inMemory();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subjectsProvider.overrideWith((ref) async => subjects),
          currentUserIdProvider.overrideWithValue('u1'),
          cacheStoreProvider.overrideWithValue(cache),
          packStorageProvider.overrideWith((ref) async => MemoryPackStorage()),
        ],
        retry: (_, _) => null,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const StudyScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Bangla: notes hero, tools and subjects with mastery', (tester) async {
    await pump(tester, const Locale('bn'));
    expect(find.text('পড়াশোনা'), findsOneWidget);
    expect(find.text('আজকের সাম্প্রতিক নোট'), findsOneWidget);
    for (final title in ['স্টাডি প্ল্যান', 'প্রশ্নব্যাংক', 'বিগত বছরের প্রশ্ন', 'ভুলের খাতা']) {
      expect(find.text(title), findsWidgets);
    }
    await tester.scrollUntilVisible(find.text('কম্পিউটার ও তথ্যপ্রযুক্তি'), 300);
    expect(find.text('বাংলা ভাষা ও সাহিত্য'), findsOneWidget);
    expect(find.text('৪২%'), findsOneWidget);
    expect(find.text('এখনও মূল্যায়ন হয়নি'), findsOneWidget);
  });

  testWidgets('English UI copy', (tester) async {
    await pump(tester, const Locale('en'));
    expect(find.text('Study'), findsOneWidget);
    expect(find.text("Today's current-affairs notes"), findsOneWidget);
    expect(find.text('Mistake notebook'), findsOneWidget);
  });
}
