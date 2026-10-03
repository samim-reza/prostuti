import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/cache/cached_fetcher.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/network/rpc.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/offline/offline_queue.dart';
import 'package:prostuti/core/utils/json.dart';
import 'package:prostuti/features/feed/data/offline_ops.dart';
import 'package:prostuti/features/feed/l10n/social_failures.dart';
import 'package:prostuti/features/friends/data/friend_models.dart';
import 'package:prostuti/features/friends/data/relationship.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Friends, requests, suggestions, search, blocking and relationship state.
///
/// First pages of the friend and request lists, relationships and the badge
/// count are cached (persisted) so the screens render offline; accepting or
/// declining a request is queued when offline.
class FriendsRepository {
  FriendsRepository(this._client, this._cache);

  final SupabaseClient _client;
  final CachedFetcher _cache;

  static const pageSize = 30;

  String? get currentUserId => _client.auth.currentUser?.id;

  String _requireUid() => currentUserId ?? (throw const AuthFailure('not_authenticated'));

  String get _scope => currentUserId ?? 'anon';

  static const listPolicy = CachePolicy(ttl: Duration(minutes: 5), negativeTtl: Duration(minutes: 1));

  // ---------------------------------------------------------------------------
  // Lists
  // ---------------------------------------------------------------------------

  /// My (or [userId]'s) friends, newest friendship first. Keyset on
  /// `friends_since`.
  /// The first page is cached (revalidated online, served offline).
  Future<List<Friend>> fetchFriends({String? userId, DateTime? before, int limit = pageSize}) {
    Future<List<Friend>> network() async {
      final rows = await _client.rpcList(
        'get_friends',
        params: {'p_user': ?userId, 'p_limit': limit, if (before != null) 'p_before': before.toUtc().toIso8601String()},
      );
      return rows.map(Friend.fromJson).toList(growable: false);
    }

    if (before != null) return network();
    return _cache.get<List<Friend>>(
      'friends:list:$_scope:${userId ?? 'me'}',
      forceRefresh: true,
      fetch: network,
      encode: (list) => [for (final f in list) f.toJson()],
      decode: (json) => _decodeList(json, Friend.fromJson),
      policy: listPolicy,
      isEmpty: (list) => list.isEmpty,
    );
  }

  List<Friend>? readCachedFriends() => _readList('friends:list:$_scope:me', Friend.fromJson);

  Future<List<FriendRequest>> fetchRequests({required bool incoming, DateTime? before, int limit = pageSize}) {
    Future<List<FriendRequest>> network() async {
      final rows = await _client.rpcList(
        'get_friend_requests',
        params: {
          'p_incoming': incoming,
          'p_limit': limit,
          if (before != null) 'p_before': before.toUtc().toIso8601String(),
        },
      );
      return rows.map((r) => FriendRequest.fromJson(r, incoming: incoming)).toList(growable: false);
    }

    if (before != null) return network();
    return _cache.get<List<FriendRequest>>(
      _requestsKey(incoming),
      forceRefresh: true,
      fetch: network,
      encode: (list) => [for (final r in list) r.toJson()],
      decode: (json) => _decodeList(json, (j) => FriendRequest.fromJson(j, incoming: incoming)),
      policy: listPolicy,
      isEmpty: (list) => list.isEmpty,
    );
  }

  String _requestsKey(bool incoming) => 'friends:requests:$_scope:${incoming ? 'in' : 'out'}';

  List<FriendRequest>? readCachedRequests({required bool incoming}) =>
      _readList(_requestsKey(incoming), (j) => FriendRequest.fromJson(j, incoming: incoming));

  List<T>? _readList<T>(String key, T Function(Map<String, dynamic>) parse) {
    if (currentUserId == null) return null;
    final entry = _cache.store.read(key);
    if (entry == null || entry.negative || entry.data is! List) return null;
    try {
      return _decodeList(entry.data, parse);
    } on Object {
      return null;
    }
  }

  static List<T> _decodeList<T>(Object? json, T Function(Map<String, dynamic>) parse) => [
    for (final e in (json as List? ?? const []).whereType<Map<dynamic, dynamic>>()) parse(Map<String, dynamic>.from(e)),
  ];

  /// Number of pending incoming requests (badge). A HEAD-style exact count —
  /// no rows are transferred.
  Future<int> incomingRequestCount() async {
    final uid = currentUserId;
    if (uid == null) return 0;
    return _cache.get<int>(
      'friends:incoming_count:$uid',
      forceRefresh: true,
      fetch: () async {
        final res = await guard(
          () => _client
              .from('friend_requests')
              .select('id')
              .eq('receiver_id', uid)
              .eq('status', 'pending')
              .limit(1)
              .count(CountOption.exact),
        );
        return res.count;
      },
      encode: (v) => v,
      decode: (j) => j is num ? j.toInt() : 0,
      policy: const CachePolicy(ttl: Duration(minutes: 1)),
    );
  }

  /// Suggestions are computed by a fairly heavy query, so they are cached for
  /// a few minutes (an empty answer is remembered for 2 minutes).
  Future<List<FriendSuggestion>> fetchSuggestions({int limit = 30, bool force = false}) {
    final uid = currentUserId ?? 'anon';
    return _cache.get<List<FriendSuggestion>>(
      'friends:suggestions:$uid',
      forceRefresh: force,
      fetch: () async {
        final rows = await _client.rpcList('get_friend_suggestions', params: {'p_limit': limit});
        return rows.map(FriendSuggestion.fromJson).toList(growable: false);
      },
      encode: (list) => [
        for (final s in list)
          {...s.user.toJson(), 'district': s.district, 'mutual_friends': s.mutualFriends, 'reason': s.reason.wire},
      ],
      decode: (json) => [
        for (final e in (json as List? ?? const []).whereType<Map<dynamic, dynamic>>())
          FriendSuggestion.fromJson(Map<String, dynamic>.from(e)),
      ],
      policy: const CachePolicy(ttl: Duration(minutes: 10)),
      isEmpty: (list) => list.isEmpty,
    );
  }

  Future<void> invalidateSuggestions() => _cache.invalidate('friends:suggestions:${currentUserId ?? 'anon'}');

  Future<List<UserSearchResult>> search(String query, {int limit = 20}) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final rows = await _client.rpcList('search_users', params: {'p_query': q, 'p_limit': limit});
    return rows.map(UserSearchResult.fromJson).toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Relationship
  // ---------------------------------------------------------------------------

  String _relKey(String userId) => 'friends:rel:$_scope:$userId';

  /// Always asks the server when online; the last answer is kept so profile
  /// buttons render offline.
  Future<Relationship> relationship(String userId) => _cache.get<Relationship>(
    _relKey(userId),
    forceRefresh: true,
    fetch: () async => Relationship.fromJson(await _client.rpcMap('get_relationship', params: {'p_user': userId})),
    encode: (r) => r.toJson(),
    decode: (j) => j is Map ? Relationship.fromJson(Map<String, dynamic>.from(j)) : Relationship.none,
    policy: CachePolicy.short,
  );

  /// Persists a locally known relationship (after an action).
  Future<void> rememberRelationship(String userId, Relationship r) async {
    if (currentUserId == null) return;
    await _cache.store.write(_relKey(userId), r.toJson(), const Duration(minutes: 2));
  }

  /// Relationship with every user in [userIds] using three parallel,
  /// index-backed selects (RLS lets me read my friendships, my requests and
  /// my blocks) — instead of N `get_relationship` calls.
  Future<Map<String, Relationship>> relationshipsFor(List<String> userIds) async {
    final me = _requireUid();
    final ids = userIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return const {};
    final list = ids.join(',');
    final results = await Future.wait([
      guard(
        () => _client
            .from('friendships')
            .select('user_a, user_b')
            .or('and(user_a.eq.$me,user_b.in.($list)),and(user_b.eq.$me,user_a.in.($list))'),
      ),
      guard(
        () => _client
            .from('friend_requests')
            .select('id, sender_id, receiver_id')
            .eq('status', 'pending')
            .or('and(sender_id.eq.$me,receiver_id.in.($list)),and(receiver_id.eq.$me,sender_id.in.($list))'),
      ),
      guard(() => _client.from('blocks').select('blocked_id').eq('blocker_id', me).inFilter('blocked_id', ids)),
    ]);
    return resolveRelationships(
      me: me,
      userIds: ids,
      friendships: results[0],
      pendingRequests: results[1],
      blocks: results[2],
    );
  }

  /// Returns the new relationship (`request_sent` with its id, or `friends`
  /// when they had already asked me).
  Future<Relationship> sendRequest(String userId) async {
    final json = await _client.rpcMap('send_friend_request', params: {'p_target': userId});
    return Relationship.fromJson(json);
  }

  Future<Relationship> respond(int requestId, {required bool accept}) async {
    final json = await _client.rpcMap('respond_friend_request', params: {'p_request': requestId, 'p_accept': accept});
    return Relationship.fromJson(json);
  }

  /// Accept/decline now, or queue it offline (the optimistic answer is
  /// returned). A replay of an already-handled request is a no-op.
  Future<Relationship> respondOrQueue(int requestId, {required String userId, required bool accept}) async {
    final result = await runOrQueue(
      SocialOps.respondRequest,
      {'request_id': requestId, 'user_id': userId, 'accept': accept},
      id: 'respond-$requestId',
      direct: () => respond(requestId, accept: accept),
    );
    return result ?? (accept ? Relationship.friends : Relationship.none);
  }

  /// Responses waiting in the outbox: user id → accepted?
  Map<String, bool> pendingResponses() => {
    for (final p in pendingPayloads(SocialOps.respondRequest)) p.str('user_id'): p.boolean('accept'),
  };

  void registerOfflineHandlers() {
    OfflineQueue.instance.register(SocialOps.respondRequest, (p) async {
      try {
        await respond(p.integer('request_id'), accept: p.boolean('accept'));
      } on NotFoundFailure {
        // Already answered (or cancelled by the sender) — nothing to replay.
      }
    });
  }

  Future<void> cancelRequest(int requestId) =>
      _client.rpcCall<void>('cancel_friend_request', params: {'p_request': requestId});

  Future<void> unfriend(String userId) => _client.rpcCall<void>('unfriend', params: {'p_user': userId});

  Future<void> block(String userId) => _client.rpcCall<void>('block_user', params: {'p_user': userId});

  Future<void> unblock(String userId) => _client.rpcCall<void>('unblock_user', params: {'p_user': userId});

  /// Opens (or creates) the 1:1 conversation and returns its id.
  Future<String> openDirectConversation(String userId) async {
    final id = await _client.rpcCall<Object?>('get_or_create_direct_conversation', params: {'p_other': userId});
    if (id == null) throw const NotFoundFailure('not_found');
    return id.toString();
  }
}

final friendsRepositoryProvider = Provider<FriendsRepository>((ref) {
  registerFailureMessages(socialFailureResolver);
  return FriendsRepository(ref.watch(supabaseProvider), ref.watch(cachedFetcherProvider))..registerOfflineHandlers();
});
