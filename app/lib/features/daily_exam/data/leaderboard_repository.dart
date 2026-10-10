import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/cache/cached_fetcher.dart';
import 'package:prostuti/core/network/rpc.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/utils/bd_time.dart';
import 'package:prostuti/features/daily_exam/data/daily_standing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Today's standing changes with every submission → short TTL (also the
/// "live" refresh interval). Past days are frozen once the day's last
/// sessions expire → long TTL; empty past days are re-checked rarely.
CachePolicy leaderboardPolicy(String isoDate, {required String todayIso}) {
  if (isoDate == todayIso) {
    return const CachePolicy(ttl: Duration(minutes: 1), negativeTtl: Duration(minutes: 1));
  }
  return const CachePolicy(ttl: Duration(hours: 12), negativeTtl: Duration(hours: 3));
}

/// The last [days] Bangladesh calendar days, newest first (today included).
List<DateTime> lastBdDays(int days, {DateTime? today}) {
  final t = today ?? BdTime.today();
  final base = DateTime.utc(t.year, t.month, t.day);
  return [for (var i = 0; i < days; i++) DateTime.utc(base.year, base.month, base.day - i)];
}

/// The caller's private daily-exam standing (`get_daily_standing`), cached
/// per user (the payload is "me") and per date.
class LeaderboardRepository {
  LeaderboardRepository(this._client, this._fetcher);

  final SupabaseClient _client;
  final CachedFetcher _fetcher;

  static String cacheKey(String userId, String isoDate) => 'daily_standing:$userId:$isoDate';

  Future<DailyStanding> fetch({required String userId, required String isoDate, bool force = false}) {
    return _fetcher.get<DailyStanding>(
      cacheKey(userId, isoDate),
      fetch: () async =>
          DailyStanding.fromJson(await _client.rpcMap('get_daily_standing', params: {'p_date': isoDate})),
      encode: (v) => v.toJson(),
      decode: (j) => DailyStanding.fromJson(Map<String, dynamic>.from(j! as Map)),
      policy: leaderboardPolicy(isoDate, todayIso: BdTime.todayIso()),
      isEmpty: (v) => v.isEmpty,
      forceRefresh: force,
    );
  }

  /// Drops one day's cached standing (after a submission).
  Future<void> invalidate(String userId, String isoDate) => _fetcher.invalidate(cacheKey(userId, isoDate));
}

final leaderboardRepositoryProvider = Provider<LeaderboardRepository>(
  (ref) => LeaderboardRepository(ref.watch(supabaseProvider), ref.watch(cachedFetcherProvider)),
);
