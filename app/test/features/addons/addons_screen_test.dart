import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_theme.dart';
import 'package:prostuti/features/addons/application/addons_providers.dart';
import 'package:prostuti/features/addons/data/addon_models.dart';
import 'package:prostuti/features/addons/presentation/screens/addons_screen.dart';

final _catalog = AddonCatalog.fromJson(const {
  'addons': [
    {
      'code': 'prostuti_pro',
      'name_bn': 'প্রস্তুতি প্রো',
      'name_en': 'Prostuti Pro',
      'description_bn': 'সব প্রিমিয়াম ফিচার একসাথে',
      'features': ['daily_exam', 'model_test'],
      'price_bdt': 249,
      'period_days': 30,
      'trial_days': 7,
      'badge': 'সেরা মূল্য',
      'color': '#F42A41',
      'icon': 'workspace_premium',
    },
    {
      'code': 'samprotik_plus',
      'name_bn': 'সাম্প্রতিক প্লাস',
      'name_en': 'Current Affairs Plus',
      'features': ['daily_exam'],
      'price_bdt': 49,
      'period_days': 30,
      'color': '#0E7C66',
      'icon': 'newspaper',
    },
  ],
  'features': [
    {'code': 'daily_exam', 'name_bn': 'দৈনিক পরীক্ষা', 'name_en': 'Daily exam'},
    {'code': 'model_test', 'name_bn': 'মডেল টেস্ট', 'name_en': 'Model tests'},
    {'code': 'daily_notes', 'name_bn': 'দৈনিক নোট', 'name_en': 'Daily notes', 'is_free': true},
  ],
});

void main() {
  setUpAll(() async {
    await initializeDateFormatting('bn');
    await initializeDateFormatting('en');
  });

  for (final dark in [false, true]) {
    testWidgets('store renders plans, promo box and every add-on (dark: $dark)', (tester) async {
      final now = DateTime.now();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            addonCatalogProvider.overrideWith((ref) async => _catalog),
            myPlansProvider.overrideWith(
              (ref) async => [
                ActivePlan(
                  addonCode: 'prostuti_pro',
                  source: EntitlementSource.trial,
                  startsAt: now.subtract(const Duration(days: 1)),
                  expiresAt: now.add(const Duration(days: 6)),
                ),
              ],
            ),
          ],
          child: MaterialApp(
            locale: const Locale('bn'),
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const AddonsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l = lookupAppLocalizations(const Locale('bn'));
      expect(find.text(l.addonsHeroTitle), findsOneWidget);
      expect(find.text(l.addonsMyPlans), findsOneWidget);
      expect(find.text(l.addonsSourceTrial), findsOneWidget);
      expect(find.text(l.addonsPromoTitle), findsOneWidget);
      await tester.scrollUntilVisible(find.text('৳৪৯/৩০ দিন'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text(l.addonsExtend), findsOneWidget); // Pro is active
      await tester.scrollUntilVisible(
        find.text(l.addonsFreeFeaturesTitle),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('দৈনিক নোট'), findsOneWidget);
    });
  }
}
