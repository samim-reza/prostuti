import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/cache/cached_fetcher.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/network/rpc.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/offline/offline_queue.dart';
import 'package:prostuti/core/utils/bd_time.dart';
import 'package:prostuti/features/study_plan/data/plan_models.dart';
import 'package:prostuti/features/study_plan/data/readiness_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A cached value read synchronously (for instant first paint).
typedef Peeked<T> = ({T value, bool fresh});

/// Study plan, daily routine and readiness — all served by Postgres RPCs
/// (`get_today_routine`, `get_plan_overview`, `get_readiness`…) except plan
/// generation, which runs in the `generate-study-plan` Edge Function.
class StudyPlanRepository {
  StudyPlanRepository(this._client, this._cache);

  final SupabaseClient _client;
  final CachedFetcher _cache;

  static const _routinePolicy = CachePolicy(ttl: Duration(minutes: 5), negativeTtl: Duration(minutes: 1));
  static const _overviewPolicy = CachePolicy(ttl: Duration(minutes: 10), negativeTtl: Duration(minutes: 1));
  static const _readinessPolicy = CachePolicy(ttl: Duration(minutes: 10));
  static const _dayPolicy = CachePolicy(ttl: Duration(minutes: 10), negativeTtl: Duration(minutes: 5));

  /// Plan generation calls an LLM; give it time before treating it as failed.
  static const generationTimeout = Duration(seconds: 120);

  static const dayColumns =
      'id, plan_id, day_date, day_index, kind, title_bn, title_en, items, target_minutes, completed_items, total_items, status';

  String get _uid => _client.auth.currentUser?.id ?? 'anon';

  // The routine is per Bangladesh day: a new key every morning means a stale
  // routine from yesterday can never be shown as "today".
  String get _routineKey => 'plan:routine:$_uid:${BdTime.todayIso()}';
  String get _overviewKey => 'plan:overview:$_uid';
  String get _readinessKey => 'plan:readiness:$_uid';

  Peeked<T>? _peek<T>(String key, T Function(Map<String, dynamic>) decode) {
    final entry = _cache.store.read(key);
    if (entry == null || entry.negative || entry.data is! Map) return null;
    try {
      return (value: decode(Map<String, dynamic>.from(entry.data! as Map)), fresh: entry.isFresh);
    } on Object {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Today's routine
  // ---------------------------------------------------------------------------
  Peeked<TodayRoutine>? peekTodayRoutine() => _peek(_routineKey, TodayRoutine.fromJson);

  Future<TodayRoutine> todayRoutine({bool force = false}) => _cache.get<TodayRoutine>(
    _routineKey,
    forceRefresh: force,
    fetch: () async => TodayRoutine.fromJson(await _client.rpcMap('get_today_routine')),
    encode: (v) => v.toJson(),
    decode: (j) => TodayRoutine.fromJson(Map<String, dynamic>.from(j! as Map)),
    policy: _routinePolicy,
    isEmpty: (v) => !v.hasPlan,
  );

  /// Persists an optimistic/merged routine so a cold start shows it instantly.
  Future<void> cacheTodayRoutine(TodayRoutine routine) =>
      _cache.store.write(_routineKey, routine.toJson(), _routinePolicy.ttl);

  // ---------------------------------------------------------------------------
  // Overview (aggregates of the whole plan; details beyond today+2 stay hidden)
  // ---------------------------------------------------------------------------
  Peeked<PlanOverview>? peekOverview() => _peek(_overviewKey, PlanOverview.fromJson);

  Future<PlanOverview> overview({bool force = false}) => _cache.get<PlanOverview>(
    _overviewKey,
    forceRefresh: force,
    fetch: () async => PlanOverview.fromJson(await _client.rpcMap('get_plan_overview')),
    encode: (v) => v.toJson(),
    decode: (j) => PlanOverview.fromJson(Map<String, dynamic>.from(j! as Map)),
    policy: _overviewPolicy,
    isEmpty: (v) => !v.hasPlan,
  );

  // ---------------------------------------------------------------------------
  // A single day. RLS hides days after today+2 → `null` means "locked".
  // Visible days are cached so they open offline.
  // ---------------------------------------------------------------------------
  String _dayKey(int dayId) => 'plan:day:$_uid:$dayId';

  Peeked<PlanDay>? peekDay(int dayId) => _peek(_dayKey(dayId), PlanDay.fromJson);

  Future<PlanDay?> day(int dayId, {bool force = false}) => _cache.get<PlanDay?>(
    _dayKey(dayId),
    forceRefresh: force,
    fetch: () async {
      final row = await guard(() => _client.from('study_plan_days').select(dayColumns).eq('id', dayId).maybeSingle());
      return row == null ? null : PlanDay.fromJson(row);
    },
    encode: (v) => v?.toJson(),
    decode: (j) => j is Map ? PlanDay.fromJson(Map<String, dynamic>.from(j)) : null,
    policy: _dayPolicy,
    isEmpty: (v) => v == null,
  );

  Future<void> cacheDay(PlanDay day) => _cache.store.write(_dayKey(day.id), day.toJson(), _dayPolicy.ttl);

  /// Offline-queue operation type for routine check-offs.
  static const completeItemOp = 'plan.complete_item';

  /// Stable op id: re-ticking the same item never queues it twice, and the
  /// RPC itself is idempotent.
  static String completeItemOpId(int dayId, String key) => 'plan_${dayId}_$key';

  /// Marks a routine item done (today or a past day only — enforced by SQL).
  /// Goes through the [OfflineQueue]: runs now when online, otherwise it is
  /// persisted and replayed later. Returns true when it already ran.
  Future<bool> completeItem(int dayId, String key) async {
    final queue = OfflineQueue.instance;
    final ran = await queue.run(completeItemOp, {'day_id': dayId, 'key': key}, id: completeItemOpId(dayId, key));
    if (!ran && ConnectivityService.instance.isOnline) unawaited(queue.flush());
    return ran;
  }

  /// The queue handler: calls `complete_plan_item` and drops stale caches.
  Future<void> completeItemNow(int dayId, String key) async {
    await _client.rpcCall<dynamic>('complete_plan_item', params: {'p_day': dayId, 'p_key': key});
    await _cache.invalidate(_overviewKey);
    await _cache.invalidate(_readinessKey);
  }

  // ---------------------------------------------------------------------------
  // Generation & re-planning
  // ---------------------------------------------------------------------------
  /// Calls the planner Edge Function. Throws an [AppFailure] on any error
  /// (including "function not deployed yet" and timeouts).
  /// [locale] (`bn`/`en`) is the UI language; tips and titles come back in it.
  Future<Map<String, dynamic>> generatePlan({required String locale, String mode = 'create'}) async {
    try {
      final res = await _client.functions
          .invoke('generate-study-plan', body: {'mode': mode, 'locale': locale})
          .timeout(generationTimeout);
      await invalidateAll();
      final data = res.data;
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        final error = map['error'];
        if (error != null) throw ServerFailure(error.toString());
        return map;
      }
      return const {};
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Queues a server-side re-plan (rate limited in SQL).
  Future<void> requestReplan(String reason) async {
    await _client.rpcCall<dynamic>('request_replan', params: {'p_reason': reason});
    await invalidateAll();
  }

  // ---------------------------------------------------------------------------
  // Readiness
  // ---------------------------------------------------------------------------
  Peeked<Readiness>? peekReadiness() => _peek(_readinessKey, Readiness.fromJson);

  Future<Readiness> readiness({bool force = false}) => _cache.get<Readiness>(
    _readinessKey,
    forceRefresh: force,
    fetch: () async => Readiness.fromJson(await _client.rpcMap('get_readiness')),
    encode: (v) => v.toJson(),
    decode: (j) => Readiness.fromJson(Map<String, dynamic>.from(j! as Map)),
    policy: _readinessPolicy,
  );

  Future<void> invalidateReadiness() => _cache.invalidate(_readinessKey);

  Future<void> invalidateAll() => _cache.invalidatePrefix('plan:');
}

final studyPlanRepositoryProvider = Provider<StudyPlanRepository>((ref) {
  final repo = StudyPlanRepository(ref.watch(supabaseProvider), ref.watch(cachedFetcherProvider));
  OfflineQueue.instance.register(StudyPlanRepository.completeItemOp, (payload) {
    final dayId = payload['day_id'];
    final key = payload['key'];
    if (dayId is! num || key is! String) return Future.value();
    return repo.completeItemNow(dayId.toInt(), key);
  });
  return repo;
});
