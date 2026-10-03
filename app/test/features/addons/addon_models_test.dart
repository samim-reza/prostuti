import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/features/addons/data/addon_models.dart';
import 'package:prostuti/features/addons/data/payment_provider.dart';

void main() {
  final now = DateTime.utc(2026, 10, 4, 12);

  Entitlement ent(int id, String code, EntitlementSource source, DateTime start, DateTime end) =>
      Entitlement(id: id, addonCode: code, source: source, startsAt: start, expiresAt: end);

  group('Addon / catalog parsing', () {
    test('parses the live add-on row shape', () {
      final a = Addon.fromJson(const {
        'code': 'prostuti_pro',
        'name_bn': 'প্রস্তুতি প্রো',
        'name_en': 'Prostuti Pro',
        'description_bn': 'সব প্রিমিয়াম ফিচার একসাথে',
        'description_en': null,
        'features': ['daily_exam', 'model_test'],
        'price_bdt': 249.00,
        'period_days': 30,
        'trial_days': 7,
        'badge': 'সেরা মূল্য',
        'color': '#F42A41',
        'icon': 'workspace_premium',
        'sort': 0,
      });
      expect(a.isPro, isTrue);
      expect(a.priceBdt, 249);
      expect(a.trialDays, 7);
      expect(a.features, ['daily_exam', 'model_test']);
      expect(a.name(bangla: false), 'Prostuti Pro');
      // English description falls back to Bangla when missing.
      expect(a.description(bangla: false), 'সব প্রিমিয়াম ফিচার একসাথে');
      expect(Addon.fromJson(a.toJson()).toJson(), a.toJson());
    });

    test('accepts numeric strings (numeric columns may arrive as text)', () {
      final a = Addon.fromJson(const {'code': 'x', 'name_bn': 'x', 'features': <String>[], 'price_bdt': '49.50'});
      expect(a.priceBdt, 49.5);
      expect(a.periodDays, 30);
      expect(a.isPro, isFalse);
    });

    test('feature names are localized, unknown codes kept', () {
      final catalog = AddonCatalog.fromJson(const {
        'addons': [
          {
            'code': 'exam_pro',
            'name_bn': 'এক্সাম প্রো',
            'features': ['model_test', 'brand_new'],
            'price_bdt': 99,
          },
        ],
        'features': [
          {'code': 'model_test', 'name_bn': 'মডেল টেস্ট', 'name_en': 'Model tests', 'is_free': false},
        ],
      });
      final addon = catalog.byCode('exam_pro')!;
      expect(catalog.featureNames(addon, bangla: true), ['মডেল টেস্ট', 'brand_new']);
      expect(catalog.featureNames(addon, bangla: false), ['Model tests', 'brand_new']);
      expect(catalog.byCode('missing'), isNull);
      expect(AddonCatalog.fromJson(catalog.toJson()).addons.single.code, 'exam_pro');
    });

    test('entitlement parsing', () {
      final e = Entitlement.fromJson(const {
        'id': 1,
        'addon_code': 'prostuti_pro',
        'source': 'trial',
        'starts_at': '2026-10-03T20:47:38.749317+00:00',
        'expires_at': '2026-10-10T20:47:38.749317+00:00',
      });
      expect(e.source, EntitlementSource.trial);
      expect(e.isActiveAt(now), isTrue);
      expect(EntitlementSource.parse('weird'), EntitlementSource.purchase);
      expect(Entitlement.fromJson(e.toJson()).expiresAt, e.expiresAt);
    });
  });

  group('mergeEntitlements', () {
    test('stacked trial + promo → one plan, current source, latest expiry', () {
      final plans = mergeEntitlements([
        ent(
          1,
          'prostuti_pro',
          EntitlementSource.trial,
          now.subtract(const Duration(days: 2)),
          now.add(const Duration(days: 5)),
        ),
        ent(
          2,
          'prostuti_pro',
          EntitlementSource.promo,
          now.add(const Duration(days: 5)),
          now.add(const Duration(days: 35)),
        ),
      ], now);
      expect(plans, hasLength(1));
      expect(plans.single.source, EntitlementSource.trial);
      expect(plans.single.isTrial, isTrue);
      expect(plans.single.expiresAt, now.add(const Duration(days: 35)));
      expect(plans.single.startsAt, now.subtract(const Duration(days: 2)));
    });

    test('drops expired and not-yet-started add-ons; sorts by expiry', () {
      final plans = mergeEntitlements([
        ent(
          1,
          'expired',
          EntitlementSource.trial,
          now.subtract(const Duration(days: 10)),
          now.subtract(const Duration(days: 1)),
        ),
        ent(2, 'future', EntitlementSource.admin, now.add(const Duration(days: 1)), now.add(const Duration(days: 9))),
        ent(
          3,
          'late',
          EntitlementSource.purchase,
          now.subtract(const Duration(days: 1)),
          now.add(const Duration(days: 20)),
        ),
        ent(
          4,
          'soon',
          EntitlementSource.promo,
          now.subtract(const Duration(days: 1)),
          now.add(const Duration(days: 2)),
        ),
      ], now);
      expect(plans.map((p) => p.addonCode), ['soon', 'late']);
    });

    test('primaryPlan prefers Prostuti Pro, else the longest', () {
      final a = ActivePlan(
        addonCode: 'exam_pro',
        source: EntitlementSource.promo,
        startsAt: now,
        expiresAt: now.add(const Duration(days: 40)),
      );
      final b = ActivePlan(
        addonCode: 'ad_free',
        source: EntitlementSource.promo,
        startsAt: now,
        expiresAt: now.add(const Duration(days: 10)),
      );
      final pro = ActivePlan(
        addonCode: Addon.proCode,
        source: EntitlementSource.trial,
        startsAt: now,
        expiresAt: now.add(const Duration(days: 3)),
      );
      expect(primaryPlan([a, b])!.addonCode, 'exam_pro');
      expect(primaryPlan([a, b, pro])!.addonCode, Addon.proCode);
      expect(primaryPlan(const []), isNull);
    });

    test('remainingFraction goes from 1 to 0', () {
      final p = ActivePlan(
        addonCode: 'x',
        source: EntitlementSource.trial,
        startsAt: now.subtract(const Duration(days: 5)),
        expiresAt: now.add(const Duration(days: 5)),
      );
      expect(p.remainingFraction(now), closeTo(0.5, 0.001));
      expect(p.remainingFraction(now.add(const Duration(days: 30))), 0);
      expect(p.remainingFraction(now.subtract(const Duration(days: 30))), 1);
    });
  });

  group('days left', () {
    test('rounds up partial days', () {
      expect(daysLeft(now.add(const Duration(days: 6, hours: 3)), now), 7);
      expect(daysLeft(now.add(const Duration(days: 7)), now), 7);
      expect(daysLeft(now.add(const Duration(minutes: 1)), now), 1);
    });

    test('is zero once expired', () {
      expect(daysLeft(now, now), 0);
      expect(daysLeft(now.subtract(const Duration(hours: 1)), now), 0);
      expect(timeLeft(now.subtract(const Duration(hours: 1)), now), Duration.zero);
    });
  });

  group('promo codes', () {
    test('normalization strips whitespace and upper-cases', () {
      expect(normalizePromoCode('  bcs 2026 \n'), 'BCS2026');
      expect(normalizePromoCode(''), '');
    });

    test('error codes map to PromoError', () {
      expect(PromoError.fromCode('promo_invalid'), PromoError.invalid);
      expect(PromoError.fromCode('promo_exhausted'), PromoError.exhausted);
      expect(PromoError.fromCode('promo_already_used'), PromoError.alreadyUsed);
      expect(PromoError.fromCode('rate_limited'), isNull);
    });

    test('redemption parsing', () {
      final r = PromoRedemption.fromJson(const {
        'addon_code': 'prostuti_pro',
        'expires_at': '2026-11-03T12:00:00Z',
        'days': 30,
      });
      expect(r.addonCode, 'prostuti_pro');
      expect(r.days, 30);
      expect(r.expiresAt, DateTime.utc(2026, 11, 3, 12));
    });
  });

  test('ManualPaymentProvider reports purchases as unavailable', () async {
    const provider = ManualPaymentProvider();
    expect(provider.isAvailable, isFalse);
    expect(provider.id, 'manual');
    final result = await provider.purchase(
      const Addon(code: 'x', nameBn: 'x', nameEn: 'x', features: [], priceBdt: 49),
    );
    expect(result, isA<PaymentUnavailable>());
  });
}
