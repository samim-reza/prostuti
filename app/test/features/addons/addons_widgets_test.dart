import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_theme.dart';
import 'package:prostuti/features/addons/data/addon_models.dart';
import 'package:prostuti/features/addons/presentation/addons_messages.dart';
import 'package:prostuti/features/addons/presentation/widgets/addon_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Widget _host(Widget child, {Locale locale = const Locale('bn')}) => MaterialApp(
  locale: locale,
  theme: AppTheme.light(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

const _pro = Addon(
  code: Addon.proCode,
  nameBn: 'প্রস্তুতি প্রো',
  nameEn: 'Prostuti Pro',
  features: ['daily_exam'],
  priceBdt: 249,
  trialDays: 7,
  badge: 'সেরা মূল্য',
  colorHex: '#F42A41',
  icon: 'workspace_premium',
);

void main() {
  group('promo error messages', () {
    for (final (locale, invalid) in [
      (const Locale('bn'), 'কোডটি সঠিক নয়, অথবা এর মেয়াদ শেষ হয়ে গেছে।'),
      (const Locale('en'), 'This code is not valid or has expired.'),
    ]) {
      testWidgets('maps backend codes to localized text (${locale.languageCode})', (tester) async {
        registerAddonsMessages();
        late BuildContext ctx;
        await tester.pumpWidget(
          _host(
            Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox();
              },
            ),
            locale: locale,
          ),
        );
        final l = lookupAppLocalizations(locale);
        expect(failureMessage(ctx, const ServerFailure('promo_invalid')), invalid);
        // Raw PostgREST error as raised by redeem_promo().
        expect(
          failureMessage(ctx, const PostgrestException(message: 'promo_exhausted', code: 'P0001')),
          l.addonsPromoExhausted,
        );
        expect(failureMessage(ctx, const ServerFailure('promo_already_used')), l.addonsPromoAlreadyUsed);
        // Unrelated codes fall through to the generic server message.
        expect(failureMessage(ctx, const ServerFailure('something_else')), l.errorServer);
        expect(addonsFailureMessage(ctx, 'nope'), isNull);
      });
    }
  });

  testWidgets('AddonCard shows Bangla price per period, badge and trial', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(AddonCard(addon: _pro, featureNames: const ['দৈনিক পরীক্ষা'], onBuy: () => taps++)));
    final l = lookupAppLocalizations(const Locale('bn'));
    expect(find.text('৳২৪৯/৩০ দিন'), findsOneWidget);
    expect(find.text('সেরা মূল্য'), findsOneWidget);
    expect(find.text('দৈনিক পরীক্ষা'), findsOneWidget);
    expect(find.text(l.addonsTrialBadge('৭')), findsOneWidget);
    await tester.tap(find.text(l.addonsBuy));
    expect(taps, 1);
  });

  testWidgets('AddonCard shows active plan strip and extend action (English)', (tester) async {
    final plan = ActivePlan(
      addonCode: Addon.proCode,
      source: EntitlementSource.promo,
      startsAt: DateTime.now().subtract(const Duration(days: 1)),
      expiresAt: DateTime.now().add(const Duration(days: 4, hours: 2)),
    );
    await tester.pumpWidget(
      _host(
        AddonCard(addon: _pro, featureNames: const [], plan: plan, onBuy: () {}),
        locale: const Locale('en'),
      ),
    );
    expect(find.text('৳249 / 30 days'), findsOneWidget);
    expect(find.text('Best value'), findsOneWidget);
    expect(find.text('Extend'), findsOneWidget);
    expect(find.textContaining('5 days left'), findsOneWidget);
    expect(find.textContaining('Promo'), findsOneWidget);
  });
}
