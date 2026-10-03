import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/cache/cached_fetcher.dart';
import 'package:prostuti/core/network/rpc.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/utils/json.dart';

/// Server-driven configuration (`public.app_config`): min app version,
/// morning routine time, ad unit ids, maintenance banner…
class RemoteConfig {
  const RemoteConfig(this.values);

  final Map<String, dynamic> values;

  String get minAppVersion => values.str('min_app_version', '1.0.0');
  String get latestAppVersion => values.str('latest_app_version', '1.0.0');
  int? get defaultScheduleId => values.intOrNull('default_schedule_id');

  /// "HH:mm" in Asia/Dhaka.
  String get morningRoutineTime => values.str('morning_routine_time', '06:30');

  Map<String, dynamic> get ads => values.obj('ads');
  bool get rewardedAdsEnabled => ads.boolean('rewarded_enabled', true);
  String get androidRewardedUnit => ads.str('android_rewarded_unit');
  String get iosRewardedUnit => ads.str('ios_rewarded_unit');

  bool get maintenance => values.obj('maintenance').boolean('enabled');
  String get maintenanceMessage => values.obj('maintenance').str('message_bn');

  Map<String, dynamic> get support => values.obj('support');

  static const fallback = RemoteConfig({});
}

final remoteConfigProvider = FutureProvider<RemoteConfig>((ref) async {
  final client = ref.watch(supabaseProvider);
  final fetcher = ref.watch(cachedFetcherProvider);
  try {
    final values = await fetcher.get<Map<String, dynamic>>(
      'remote_config',
      fetch: () async {
        final rows = await guard(() => client.from('app_config').select('key, value'));
        return {for (final r in rows) r['key'] as String: r['value']};
      },
      encode: (v) => v,
      decode: (j) => Map<String, dynamic>.from(j! as Map),
      policy: const CachePolicy(ttl: Duration(hours: 1)),
    );
    return RemoteConfig(values);
  } on Object {
    return RemoteConfig.fallback;
  }
});

/// Semantic-version comparison: true when [current] < [minimum].
bool isVersionBelow(String current, String minimum) {
  List<int> parse(String v) => v.split('+').first.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  final a = parse(current);
  final b = parse(minimum);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x < y;
  }
  return false;
}
