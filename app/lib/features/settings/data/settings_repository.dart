import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/cache/cache_store.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/network/rpc.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/pagination/paged_state.dart';
import 'package:prostuti/core/utils/json.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Someone the signed-in user has blocked.
@immutable
class BlockedUser {
  const BlockedUser({required this.id, required this.username, required this.blockedAt, this.fullName, this.avatarUrl});

  factory BlockedUser.fromJson(Map<String, dynamic> j) => BlockedUser(
    id: j.str('id'),
    username: j.str('username'),
    fullName: j.strOrNull('full_name'),
    avatarUrl: j.strOrNull('avatar_url'),
    blockedAt: j.dateOr('blocked_at', DateTime.now()),
  );

  final String id;
  final String username;
  final String? fullName;
  final String? avatarUrl;
  final DateTime blockedAt;

  String get displayName => (fullName?.trim().isNotEmpty ?? false) ? fullName!.trim() : username;

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'full_name': fullName,
    'avatar_url': avatarUrl,
    'blocked_at': blockedAt.toUtc().toIso8601String(),
  };
}

/// Joins `blocks` rows with the matching `profiles` rows (profiles that no
/// longer exist are skipped). Keeps the order of [blocks].
List<BlockedUser> joinBlockedProfiles(List<Map<String, dynamic>> blocks, List<Map<String, dynamic>> profiles) {
  final byId = {for (final p in profiles) p.str('id'): p};
  return [
    for (final b in blocks)
      if (byId[b.str('blocked_id')] case final p?)
        BlockedUser(
          id: p.str('id'),
          username: p.str('username'),
          fullName: p.strOrNull('full_name'),
          avatarUrl: p.strOrNull('avatar_url'),
          blockedAt: b.dateOr('created_at', DateTime.now()),
        ),
  ];
}

class SettingsRepository {
  SettingsRepository(this._client, this._store);

  final SupabaseClient _client;
  final CacheStore _store;

  String? get _uid => _client.auth.currentUser?.id;
  static String _blockedKey(String uid) => 'blocked_users:$uid';

  /// Last-seen first page of the block list (offline / instant paint).
  List<BlockedUser>? readCachedBlocked() {
    final uid = _uid;
    final raw = uid == null ? null : _store.read(_blockedKey(uid))?.data;
    if (raw is! List) return null;
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => BlockedUser.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> writeCachedBlocked(List<BlockedUser> users) async {
    final uid = _uid;
    if (uid == null) return;
    await _store.write(
      _blockedKey(uid),
      users.take(pageSize).map((u) => u.toJson()).toList(),
      const Duration(days: 30),
    );
  }

  static const pageSize = 30;

  /// Keyset page of the caller's block list, newest first.
  Future<PageResult<BlockedUser, DateTime>> blockedPage(DateTime? before) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthFailure('not_authenticated');
    final blocks = await guard(() {
      var q = _client.from('blocks').select('blocked_id, created_at').eq('blocker_id', uid);
      if (before != null) q = q.lt('created_at', before.toUtc().toIso8601String());
      return q.order('created_at', ascending: false).limit(pageSize);
    });
    if (blocks.isEmpty) return const PageResult([], null);
    final ids = blocks.map((b) => b.str('blocked_id')).toList(growable: false);
    final profiles = await guard(
      () => _client.from('profiles').select('id, username, full_name, avatar_url').inFilter('id', ids),
    );
    final users = joinBlockedProfiles(blocks, profiles);
    final last = blocks.last.date('created_at');
    return PageResult(users, blocks.length < pageSize ? null : last);
  }

  Future<void> unblock(String userId) => _client.rpcCall<void>('unblock_user', params: {'p_user': userId});

  Future<void> updatePassword(String password) =>
      guard(() => _client.auth.updateUser(UserAttributes(password: password)));
}

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(supabaseProvider), ref.watch(cacheStoreProvider)),
);
