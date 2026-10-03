import 'package:flutter/material.dart';
import 'package:prostuti/core/utils/json.dart';

/// A purchasable bundle of features (mirrors `public.addons`).
@immutable
class Addon {
  const Addon({
    required this.code,
    required this.nameBn,
    required this.nameEn,
    required this.features,
    required this.priceBdt,
    this.descriptionBn,
    this.descriptionEn,
    this.periodDays = 30,
    this.trialDays = 0,
    this.badge,
    this.colorHex,
    this.icon,
    this.sort = 0,
  });

  factory Addon.fromJson(Map<String, dynamic> j) => Addon(
    code: j.str('code'),
    nameBn: j.str('name_bn'),
    nameEn: j.str('name_en', j.str('name_bn')),
    descriptionBn: j.strOrNull('description_bn'),
    descriptionEn: j.strOrNull('description_en'),
    features: j.strings('features'),
    priceBdt: j.dbl('price_bdt'),
    periodDays: j.integer('period_days', 30),
    trialDays: j.integer('trial_days'),
    badge: j.strOrNull('badge'),
    colorHex: j.strOrNull('color'),
    icon: j.strOrNull('icon'),
    sort: j.integer('sort'),
  );

  /// Explicit column list (smaller payloads, stable contract).
  static const columns =
      'code, name_bn, name_en, description_bn, description_en, features, price_bdt, period_days, '
      'trial_days, badge, color, icon, sort';

  /// The all-in-one plan that the store highlights.
  static const proCode = 'prostuti_pro';

  final String code;
  final String nameBn;
  final String nameEn;
  final String? descriptionBn;
  final String? descriptionEn;
  final List<String> features;
  final double priceBdt;
  final int periodDays;
  final int trialDays;
  final String? badge;
  final String? colorHex;
  final String? icon;
  final int sort;

  bool get isPro => code == proCode;
  bool get isFree => priceBdt <= 0;

  String name({required bool bangla}) => bangla ? nameBn : (nameEn.isEmpty ? nameBn : nameEn);

  String? description({required bool bangla}) {
    final value = bangla ? descriptionBn : (descriptionEn ?? descriptionBn);
    return (value == null || value.trim().isEmpty) ? null : value.trim();
  }

  IconData get iconData => addonIcons[icon] ?? Icons.extension_rounded;

  Map<String, dynamic> toJson() => {
    'code': code,
    'name_bn': nameBn,
    'name_en': nameEn,
    'description_bn': descriptionBn,
    'description_en': descriptionEn,
    'features': features,
    'price_bdt': priceBdt,
    'period_days': periodDays,
    'trial_days': trialDays,
    'badge': badge,
    'color': colorHex,
    'icon': icon,
    'sort': sort,
  };
}

/// Icon names stored in `addons.icon` → Material icons (const, tree-shakeable).
const addonIcons = <String, IconData>{
  'newspaper': Icons.newspaper_rounded,
  'quiz': Icons.quiz_rounded,
  'auto_awesome': Icons.auto_awesome_rounded,
  'block': Icons.block_rounded,
  'workspace_premium': Icons.workspace_premium_rounded,
  'school': Icons.school_rounded,
  'star': Icons.star_rounded,
};

/// A product feature (mirrors `public.features`).
@immutable
class FeatureInfo {
  const FeatureInfo({
    required this.code,
    required this.nameBn,
    required this.nameEn,
    this.isFree = false,
    this.freeDailyQuota,
    this.sort = 0,
  });

  factory FeatureInfo.fromJson(Map<String, dynamic> j) => FeatureInfo(
    code: j.str('code'),
    nameBn: j.str('name_bn'),
    nameEn: j.str('name_en', j.str('name_bn')),
    isFree: j.boolean('is_free'),
    freeDailyQuota: j.intOrNull('free_daily_quota'),
    sort: j.integer('sort'),
  );

  static const columns = 'code, name_bn, name_en, is_free, free_daily_quota, sort';

  final String code;
  final String nameBn;
  final String nameEn;
  final bool isFree;
  final int? freeDailyQuota;
  final int sort;

  String name({required bool bangla}) => bangla ? nameBn : (nameEn.isEmpty ? nameBn : nameEn);

  Map<String, dynamic> toJson() => {
    'code': code,
    'name_bn': nameBn,
    'name_en': nameEn,
    'is_free': isFree,
    'free_daily_quota': freeDailyQuota,
    'sort': sort,
  };
}

/// Add-ons plus the feature dictionary used to describe them.
@immutable
class AddonCatalog {
  const AddonCatalog({required this.addons, required this.features});

  factory AddonCatalog.fromJson(Map<String, dynamic> j) => AddonCatalog(
    addons: j.list('addons', Addon.fromJson),
    features: {for (final f in j.list('features', FeatureInfo.fromJson)) f.code: f},
  );

  static const empty = AddonCatalog(addons: [], features: {});

  /// Sorted by `sort` (the server already orders, this keeps it stable).
  final List<Addon> addons;
  final Map<String, FeatureInfo> features;

  Addon? byCode(String code) {
    for (final a in addons) {
      if (a.code == code) return a;
    }
    return null;
  }

  /// Localized names of the features an add-on unlocks (unknown codes are
  /// shown as-is so a newly added feature never disappears from the card).
  List<String> featureNames(Addon addon, {required bool bangla}) => [
    for (final code in addon.features) features[code]?.name(bangla: bangla) ?? code,
  ];

  Map<String, dynamic> toJson() => {
    'addons': addons.map((a) => a.toJson()).toList(),
    'features': features.values.map((f) => f.toJson()).toList(),
  };
}

/// How an entitlement was obtained (mirrors the SQL check constraint).
enum EntitlementSource {
  trial,
  purchase,
  promo,
  admin;

  static EntitlementSource parse(String? v) =>
      EntitlementSource.values.firstWhere((e) => e.name == v, orElse: () => EntitlementSource.purchase);
}

/// One row of `public.user_entitlements`.
@immutable
class Entitlement {
  const Entitlement({
    required this.id,
    required this.addonCode,
    required this.source,
    required this.startsAt,
    required this.expiresAt,
  });

  factory Entitlement.fromJson(Map<String, dynamic> j) {
    final starts = j.dateOr('starts_at', DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    return Entitlement(
      id: j.integer('id'),
      addonCode: j.str('addon_code'),
      source: EntitlementSource.parse(j.strOrNull('source')),
      startsAt: starts,
      expiresAt: j.dateOr('expires_at', starts),
    );
  }

  static const columns = 'id, addon_code, source, starts_at, expires_at';

  final int id;
  final String addonCode;
  final EntitlementSource source;
  final DateTime startsAt;
  final DateTime expiresAt;

  bool isActiveAt(DateTime now) => !startsAt.isAfter(now) && expiresAt.isAfter(now);

  Map<String, dynamic> toJson() => {
    'id': id,
    'addon_code': addonCode,
    'source': source.name,
    'starts_at': startsAt.toUtc().toIso8601String(),
    'expires_at': expiresAt.toUtc().toIso8601String(),
  };
}

/// The user's effective plan for one add-on. Entitlements for the same add-on
/// stack (a promo code redeemed during a trial starts when the trial ends), so
/// the plan runs from the earliest running start to the latest expiry.
@immutable
class ActivePlan {
  const ActivePlan({required this.addonCode, required this.source, required this.startsAt, required this.expiresAt});

  final String addonCode;

  /// Source of the entitlement that is running right now.
  final EntitlementSource source;
  final DateTime startsAt;
  final DateTime expiresAt;

  bool get isTrial => source == EntitlementSource.trial;

  /// 1.0 at the start, 0.0 at expiry.
  double remainingFraction(DateTime now) {
    final total = expiresAt.difference(startsAt).inSeconds;
    if (total <= 0) return 0;
    return (expiresAt.difference(now).inSeconds / total).clamp(0.0, 1.0);
  }
}

/// Collapses raw entitlements into one [ActivePlan] per add-on, keeping only
/// add-ons that are running at [now]. Sorted by expiry (soonest first).
///
/// O(n) — one pass to group, one pass to build.
List<ActivePlan> mergeEntitlements(Iterable<Entitlement> rows, DateTime now) {
  final byAddon = <String, List<Entitlement>>{};
  for (final e in rows) {
    if (!e.expiresAt.isAfter(now)) continue;
    (byAddon[e.addonCode] ??= []).add(e);
  }
  final plans = <ActivePlan>[];
  byAddon.forEach((code, list) {
    Entitlement? current;
    var latest = list.first.expiresAt;
    var earliest = list.first.startsAt;
    for (final e in list) {
      if (e.expiresAt.isAfter(latest)) latest = e.expiresAt;
      if (e.startsAt.isBefore(earliest)) earliest = e.startsAt;
      if (e.isActiveAt(now) && (current == null || e.startsAt.isBefore(current.startsAt))) current = e;
    }
    // Only future-dated entitlements (not started yet) → not active.
    if (current == null) return;
    plans.add(ActivePlan(addonCode: code, source: current.source, startsAt: earliest, expiresAt: latest));
  });
  plans.sort((a, b) => a.expiresAt.compareTo(b.expiresAt));
  return plans;
}

/// Picks the plan to feature on the profile: Prostuti Pro first, otherwise
/// the one that lasts longest.
ActivePlan? primaryPlan(List<ActivePlan> plans) {
  if (plans.isEmpty) return null;
  for (final p in plans) {
    if (p.addonCode == Addon.proCode) return p;
  }
  return plans.reduce((a, b) => a.expiresAt.isAfter(b.expiresAt) ? a : b);
}

/// Time left until [expiresAt] (never negative).
Duration timeLeft(DateTime expiresAt, DateTime now) {
  final d = expiresAt.difference(now);
  return d.isNegative ? Duration.zero : d;
}

/// Whole days left, rounded **up** (6 days 3 hours → 7), 0 once expired.
int daysLeft(DateTime expiresAt, DateTime now) {
  final left = timeLeft(expiresAt, now);
  if (left == Duration.zero) return 0;
  return (left.inMinutes / Duration.minutesPerDay).ceil();
}

/// Result of `redeem_promo`.
@immutable
class PromoRedemption {
  const PromoRedemption({required this.addonCode, required this.expiresAt, required this.days});

  factory PromoRedemption.fromJson(Map<String, dynamic> j) => PromoRedemption(
    addonCode: j.str('addon_code'),
    expiresAt: j.dateOr('expires_at', DateTime.now()),
    days: j.integer('days'),
  );

  final String addonCode;
  final DateTime expiresAt;
  final int days;
}

/// Business errors raised by `redeem_promo`.
enum PromoError {
  invalid('promo_invalid'),
  exhausted('promo_exhausted'),
  alreadyUsed('promo_already_used');

  PromoError(this.code);
  final String code;

  static PromoError? fromCode(String code) {
    for (final e in values) {
      if (e.code == code) return e;
    }
    return null;
  }
}

/// Promo codes are case-insensitive on the server (citext); normalise what the
/// user typed so stray spaces or dashes from copy/paste don't fail.
String normalizePromoCode(String raw) => raw.replaceAll(RegExp(r'\s+'), '').trim().toUpperCase();
