import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/cache/cached_fetcher.dart';
import 'package:prostuti/core/config/app_constants.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/network/rpc.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/offline/offline_queue.dart';
import 'package:prostuti/features/notifications/data/app_notification.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// In-app notification inbox: keyset pages (first page persisted for
/// offline), queued read/delete actions, Realtime subscription.
class NotificationsRepository {
  NotificationsRepository(this._client, this._cache);

  final SupabaseClient _client;
  final CachedFetcher _cache;

  static const pageSize = AppConstants.pageSize;

  /// OfflineQueue operation types (all idempotent).
  static const markReadOp = 'notifications.markRead';
  static const markAllReadOp = 'notifications.markAllRead';
  static const deleteOp = 'notifications.delete';

  static const _offlinePolicy = CachePolicy(ttl: Duration(days: 14), negativeTtl: Duration(minutes: 1));

  String? get currentUserId => _client.auth.currentUser?.id;

  String _requireUid() => currentUserId ?? (throw const AuthFailure('not_authenticated'));

  void registerQueueHandlers(OfflineQueue queue) {
    queue
      ..register(markReadOp, (p) => _markRead((p['id'] as num).toInt()))
      ..register(markAllReadOp, (_) => _markAllRead())
      ..register(deleteOp, (p) => _delete((p['id'] as num).toInt()));
  }

  String _firstPageKey(String uid) => 'notifications:first:$uid';

  /// Newest first, keyset by `(created_at, id)`. The first page is
  /// network-first with a persisted copy for offline use.
  Future<List<AppNotification>> fetchPage({NotificationCursor? before, int limit = pageSize}) {
    final uid = _requireUid();
    Future<List<AppNotification>> load() async {
      final rows = await guard(() {
        var q = _client.from('notifications').select(AppNotification.columns).eq('user_id', uid);
        if (before != null) {
          final ts = before.createdAt.toUtc().toIso8601String();
          q = q.or('created_at.lt.$ts,and(created_at.eq.$ts,id.lt.${before.id})');
        }
        return q.order('created_at', ascending: false).order('id', ascending: false).limit(limit);
      });
      return rows.map(AppNotification.fromJson).toList(growable: false);
    }

    if (before != null) return load();
    return _cache.get<List<AppNotification>>(
      _firstPageKey(uid),
      forceRefresh: true,
      fetch: load,
      encode: _encode,
      decode: _decode,
      policy: _offlinePolicy,
      isEmpty: (l) => l.isEmpty,
    );
  }

  List<AppNotification>? cachedFirstPage() {
    final uid = currentUserId;
    final raw = uid == null ? null : _cache.store.read(_firstPageKey(uid))?.data;
    if (raw == null) return null;
    try {
      return _decode(raw);
    } on Object {
      return null;
    }
  }

  /// Persists the live (Realtime-updated) first page when the screen closes.
  Future<void> saveFirstPage(List<AppNotification> items) async {
    final uid = currentUserId;
    if (uid == null || items.isEmpty) return;
    await _cache.store.write(_firstPageKey(uid), _encode(items.take(pageSize).toList()), _offlinePolicy.ttl);
  }

  static Object? _encode(List<AppNotification> l) => [for (final n in l) n.toJson()];
  static List<AppNotification> _decode(Object? j) => [
    for (final e in (j! as List)) AppNotification.fromJson(Map<String, dynamic>.from(e as Map)),
  ];

  /// Unread badge count (partial index scan); last value kept for offline.
  Future<int> unreadCount() {
    final uid = _requireUid();
    return _cache.get<int>(
      'notifications:unread:$uid',
      forceRefresh: true,
      fetch: () => guard(() => _client.from('notifications').count().eq('user_id', uid).isFilter('read_at', null)),
      encode: (n) => n,
      decode: (j) => (j as num?)?.toInt() ?? 0,
      policy: _offlinePolicy,
    );
  }

  int? cachedUnreadCount() {
    final uid = currentUserId;
    final raw = uid == null ? null : _cache.store.read('notifications:unread:$uid')?.data;
    return raw is num ? raw.toInt() : null;
  }

  Future<void> _markRead(int id) => guard(
    () => _client
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id)
        .isFilter('read_at', null),
  );

  Future<void> _markAllRead() => _client.rpcCall<void>('mark_notifications_read', params: {'p_ids': null});

  Future<void> _delete(int id) => guard(() => _client.from('notifications').delete().eq('id', id));

  /// INSERT + UPDATE on the user's own rows (`user_id=eq.<uid>`).
  RealtimeChannel subscribe(
    String uid, {
    required void Function(PostgresChangeEvent event, Map<String, dynamic> row) onChange,
    required void Function() onResubscribed,
  }) {
    final filter = PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid);
    var joins = 0;
    return _client
        .channel('notifications:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: filter,
          callback: (p) => onChange(PostgresChangeEvent.insert, p.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'notifications',
          filter: filter,
          callback: (p) => onChange(PostgresChangeEvent.update, p.newRecord),
        )
        .subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.subscribed && joins++ > 0) onResubscribed();
        });
  }

  Future<void> removeChannel(RealtimeChannel channel) async {
    try {
      await _client.removeChannel(channel);
    } on Object {
      // Already closed.
    }
  }
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) =>
      NotificationsRepository(ref.watch(supabaseProvider), ref.watch(cachedFetcherProvider))
        ..registerQueueHandlers(ref.watch(offlineQueueProvider)),
);
