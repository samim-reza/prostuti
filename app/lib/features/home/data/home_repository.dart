import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/cache/cached_fetcher.dart';
import 'package:prostuti/core/network/rpc.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/utils/bd_time.dart';
import 'package:prostuti/features/home/data/home_models.dart';
import 'package:prostuti/features/study_plan/data/study_plan_repository.dart' show Peeked;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Home-only reads (notes digest, trial). Everything is persisted in the
/// two-level cache so a cold start — even offline — paints the full Home.
class HomeRepository {
  HomeRepository(this._client, this._cache);

  final SupabaseClient _client;
  final CachedFetcher _cache;

  // Notes arrive around 06:00; until then "empty" is remembered only briefly.
  static const _notesPolicy = CachePolicy(ttl: Duration(minutes: 15), negativeTtl: Duration(minutes: 3));
  static const _trialPolicy = CachePolicy(ttl: Duration(minutes: 30));

  String get _uid => _client.auth.currentUser?.id ?? 'anon';
  String get _notesKey => 'home:notes:$_uid:${BdTime.todayIso()}';
  String get _trialKey => 'home:trial:$_uid';

  Peeked<T>? _peek<T>(String key, T Function(Map<String, dynamic>) decode) {
    final entry = _cache.store.read(key);
    if (entry == null || entry.negative || entry.data is! Map) return null;
    try {
      return (value: decode(Map<String, dynamic>.from(entry.data! as Map)), fresh: entry.isFresh);
    } on Object {
      return null;
    }
  }

  Peeked<NotesDigest>? peekNotes() => _peek(_notesKey, NotesDigest.fromJson);

  Future<NotesDigest> notes({bool force = false}) => _cache.get<NotesDigest>(
    _notesKey,
    forceRefresh: force,
    fetch: () async => NotesDigest.fromRpc(await _client.rpcMap('get_today_notes')),
    encode: (v) => v.toJson(),
    decode: (j) => NotesDigest.fromJson(Map<String, dynamic>.from(j! as Map)),
    policy: _notesPolicy,
    isEmpty: (v) => v.isEmpty,
  );

  Peeked<TrialStatus>? peekTrial() => _peek(_trialKey, TrialStatus.fromJson);

  Future<TrialStatus> trial({bool force = false}) => _cache.get<TrialStatus>(
    _trialKey,
    forceRefresh: force,
    fetch: () async {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return TrialStatus.none;
      final now = DateTime.now().toUtc();
      final rows = await guard(
        () => _client
            .from('user_entitlements')
            .select('addon_code, source, expires_at')
            .eq('user_id', uid)
            .gt('expires_at', now.toIso8601String()),
      );
      return TrialStatus(trialFromEntitlements(rows, now));
    },
    encode: (v) => v.toJson(),
    decode: (j) => TrialStatus.fromJson(Map<String, dynamic>.from(j! as Map)),
    policy: _trialPolicy,
  );
}

final homeRepositoryProvider = Provider<HomeRepository>(
  (ref) => HomeRepository(ref.watch(supabaseProvider), ref.watch(cachedFetcherProvider)),
);
