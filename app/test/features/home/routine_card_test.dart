import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_theme.dart';
import 'package:prostuti/features/home/presentation/widgets/routine_card.dart';
import 'package:prostuti/features/study_plan/application/plan_providers.dart';
import 'package:prostuti/features/study_plan/application/topic_lookup.dart';
import 'package:prostuti/features/study_plan/data/plan_models.dart';

class _FakeRoutine extends TodayRoutineNotifier {
  _FakeRoutine(this.initial);

  final TodayRoutine initial;
  final ticked = <String>[];

  @override
  FutureOr<TodayRoutine> build() => initial;

  @override
  Future<bool> completeItem(PlanItem item) async {
    ticked.add(item.key);
    final today = state.value!.today!;
    state = AsyncData(state.value!.withToday(setItemDone(today, item.key)));
    return true;
  }
}

TodayRoutine _routine() => TodayRoutine(
  hasPlan: true,
  today: PlanDay(
    id: 1,
    date: DateTime.utc(2026, 10, 4),
    kind: PlanDayKind.study,
    titleBn: 'বাংলা ব্যাকরণের দিন',
    titleEn: 'Bangla grammar day',
    targetMinutes: 120,
    totalItems: 2,
    items: const [
      PlanItem(key: 'a', type: PlanItemType.read, titleBn: 'সন্ধি পড়ুন', titleEn: 'Read sandhi', minutes: 40),
      PlanItem(key: 'b', type: PlanItemType.practice, titleBn: 'সন্ধি অনুশীলন', titleEn: 'Practise sandhi', count: 20),
    ],
  ),
  upcoming: [PlanDayBrief(id: 2, date: DateTime.utc(2026, 10, 5), kind: PlanDayKind.revision, titleBn: 'রিভিশন')],
);

Widget _app(_FakeRoutine fake, {Locale locale = const Locale('bn')}) => ProviderScope(
  overrides: [todayRoutineProvider.overrideWith(() => fake), topicLookupProvider.overrideWithValue(TopicLookup.empty)],
  child: MaterialApp(
    theme: AppTheme.light(),
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: const Scaffold(body: SingleChildScrollView(child: RoutineCard())),
  ),
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('bn');
    await initializeDateFormatting('en');
  });

  testWidgets('shows today’s checklist in Bangla with Bangla digits', (tester) async {
    final fake = _FakeRoutine(_routine());
    await tester.pumpWidget(_app(fake));
    await tester.pumpAndSettle();

    expect(find.text('আজকের রুটিন'), findsOneWidget);
    expect(find.text('বাংলা ব্যাকরণের দিন'), findsOneWidget);
    expect(find.text('সন্ধি পড়ুন'), findsOneWidget);
    expect(find.textContaining('০/২'), findsOneWidget);
    expect(find.text('আগামীকাল'), findsOneWidget);
  });

  testWidgets('ticking an item completes it optimistically', (tester) async {
    final fake = _FakeRoutine(_routine());
    await tester.pumpWidget(_app(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('সম্পন্ন হিসেবে চিহ্নিত করুন').first);
    await tester.pumpAndSettle();

    expect(fake.ticked, ['a']);
    expect(find.textContaining('১/২'), findsOneWidget);
  });

  testWidgets('English UI shows English titles', (tester) async {
    await tester.pumpWidget(_app(_FakeRoutine(_routine()), locale: const Locale('en')));
    await tester.pumpAndSettle();
    expect(find.text('Bangla grammar day'), findsOneWidget);
    expect(find.text('Read sandhi'), findsOneWidget);
  });

  testWidgets('no plan → create-plan call to action', (tester) async {
    await tester.pumpWidget(_app(_FakeRoutine(TodayRoutine.empty)));
    await tester.pumpAndSettle();
    expect(find.text('আপনার এআই স্টাডি প্ল্যান তৈরি করুন'), findsOneWidget);
    expect(find.text('প্ল্যান তৈরি করুন'), findsOneWidget);
  });
}
