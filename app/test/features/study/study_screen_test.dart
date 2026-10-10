import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/core/cache/cache_store.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:prostuti/features/onboarding/data/onboarding_repository.dart';
import 'package:prostuti/features/profile/data/profile.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';
import 'package:prostuti/features/question_bank/data/offline_pack_store.dart';
import 'package:prostuti/features/question_bank/data/question_bank_repository.dart';
import 'package:prostuti/features/study/presentation/screens/study_screen.dart';
import 'package:prostuti/features/study_plan/application/daily_advice_providers.dart';
import 'package:prostuti/features/study_plan/application/plan_providers.dart';
import 'package:prostuti/features/study_plan/data/daily_advice_models.dart';
import 'package:prostuti/features/study_plan/data/plan_models.dart';
import 'package:prostuti/features/study_plan/data/readiness_models.dart';

class _NoPlan extends TodayRoutineNotifier {
  @override
  FutureOr<TodayRoutine> build() => TodayRoutine.empty;
}

class _Readiness extends ReadinessNotifier {
  @override
  FutureOr<Readiness> build() => const Readiness(readiness: 17, estimatedScore: 30);
}

class _NoAdvice extends DailyAdviceNotifier {
  @override
  FutureOr<DailyAdvice> build() => DailyAdvice.empty('bn');
}

class _Profile extends CurrentProfileNotifier {
  @override
  Future<Profile?> build() async => const Profile(id: 'u1', username: 'rahim', onboardingStep: OnboardingStep.done);
}

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
          todayRoutineProvider.overrideWith(_NoPlan.new),
          readinessProvider.overrideWith(_Readiness.new),
          dailyAdviceProvider.overrideWith(_NoAdvice.new),
          currentProfileProvider.overrideWith(_Profile.new),
          examSchedulesProvider.overrideWith((ref) async => const <ExamSchedule>[]),
          setupStatusProvider.overrideWith((ref) async => SetupStatus.complete),
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

  testWidgets('Bangla: routine, tools (no previous-year list) and subjects with mastery', (tester) async {
    await pump(tester, const Locale('bn'));
    expect(find.text('পড়াশোনা'), findsOneWidget);
    // The plan cards moved here from Home; without a plan: "create plan".
    expect(find.text('প্ল্যান তৈরি করুন'), findsOneWidget);
    expect(find.text('আজকের সাম্প্রতিক নোট'), findsNothing);
    await tester.scrollUntilVisible(find.text('ভুলের খাতা'), 300);
    for (final title in ['স্টাডি প্ল্যান', 'প্রশ্নব্যাংক', 'মডেল টেস্ট', 'ভুলের খাতা']) {
      expect(find.text(title), findsWidgets);
    }
    expect(find.text('বিগত বছরের প্রশ্ন'), findsNothing);
    await tester.scrollUntilVisible(find.text('কম্পিউটার ও তথ্যপ্রযুক্তি'), 300);
    expect(find.text('বাংলা ভাষা ও সাহিত্য'), findsOneWidget);
    expect(find.text('৪২%'), findsOneWidget);
    expect(find.text('এখনও মূল্যায়ন হয়নি'), findsOneWidget);
  });

  testWidgets('English UI copy', (tester) async {
    await pump(tester, const Locale('en'));
    expect(find.text('Study'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Mistake notebook'), 300);
    expect(find.text('Mistake notebook'), findsOneWidget);
  });
}
