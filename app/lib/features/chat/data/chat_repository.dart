import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/cache/cached_fetcher.dart';
import 'package:prostuti/core/config/app_constants.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/network/rpc.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/offline/offline_queue.dart';
import 'package:prostuti/features/chat/data/chat_models.dart';
import 'package:prostuti/features/profile/data/profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Outcome of a queued (possibly offline) send, reported by the queue handler
/// so open threads can flip "sending…" bubbles even for replays.
@immutable
sealed class OutboxEvent {
  const OutboxEvent();
}

final class MessageDelivered extends OutboxEvent {
  const MessageDelivered(this.message);
  final ChatMessage message;
}

/// The server refused the message for good (blocked, not a member …).
final class MessageRejected extends OutboxEvent {
  const MessageRejected(this.messageId, this.conversationId, this.failure);
  final String messageId;
  final String conversationId;
  final AppFailure failure;
}

/// Every Supabase call of the chat feature (tables, RPCs, storage, Realtime),
/// with offline-first reads (CachedFetcher) and queued writes (OfflineQueue).
class ChatRepository {
  ChatRepository(this._client, this._cache);

  final SupabaseClient _client;
  final CachedFetcher _cache;
  // Synchronous: a send's Future completes with its bubble already updated.
  final _outbox = StreamController<OutboxEvent>.broadcast(sync: true);

  static const pageSize = AppConstants.chatPageSize;

  /// The backend's limit for `create_group_conversation` (excluding the creator).
  static const maxGroupMembers = 49;

  /// OfflineQueue operation types.
  static const sendOp = 'chat.send';
  static const markReadOp = 'chat.markRead';

  /// Latest cached pages live long: they are what renders offline.
  static const _offlinePolicy = CachePolicy(ttl: Duration(days: 14), negativeTtl: Duration(minutes: 1));

  String? get currentUserId => _client.auth.currentUser?.id;

  String _requireUid() => currentUserId ?? (throw const AuthFailure('not_authenticated'));

  Stream<OutboxEvent> get outbox => _outbox.stream;

  /// Registers the replay handlers once (called by the provider).
  void registerQueueHandlers(OfflineQueue queue) {
    queue
      ..register(sendOp, _replaySend)
      ..register(markReadOp, (p) => markRead('${p['conversation_id']}'));
  }

  Future<void> _replaySend(Map<String, dynamic> payload) async {
    final draft = ChatMessage.fromQueuePayload(payload);
    try {
      final saved = await send(draft);
      _emit(MessageDelivered(saved));
    } on ConflictFailure {
      // Same client id already stored (an earlier attempt's response got lost).
      _emit(MessageDelivered(draft.copyWith(status: MessageStatus.sent)));
    } on AppFailure catch (f) {
      final transient = f is NetworkFailure || f is RateLimitFailure || f is ServerFailure;
      if (!transient) _emit(MessageRejected(draft.id, draft.conversationId, f));
      rethrow;
    }
  }

  void _emit(OutboxEvent e) {
    if (!_outbox.isClosed) _outbox.add(e);
  }

  void dispose() => unawaited(_outbox.close());

  // ---------------------------------------------------------------------------
  // Conversations
  // ---------------------------------------------------------------------------

  String _inboxKey(String uid) => 'chat:inbox:$uid';

  /// Inbox page, newest activity first. Keyset cursor = `last_message_at`.
  /// The first page is network-first with a persisted copy for offline use.
  Future<List<ConversationSummary>> fetchConversations({DateTime? before, int limit = pageSize}) {
    Future<List<ConversationSummary>> load() async {
      final rows = await _client.rpcList(
        'get_conversations',
        params: {'p_limit': limit, 'p_before': before?.toUtc().toIso8601String()},
      );
      return rows.map(ConversationSummary.fromJson).toList(growable: false);
    }

    if (before != null) return load();
    return _cache.get<List<ConversationSummary>>(
      _inboxKey(_requireUid()),
      forceRefresh: true,
      fetch: load,
      encode: _encodeInbox,
      decode: _decodeInbox,
      policy: _offlinePolicy,
      isEmpty: (l) => l.isEmpty,
    );
  }

  /// Instant first paint (and offline) copy of the inbox.
  List<ConversationSummary>? cachedInbox() {
    final uid = currentUserId;
    if (uid == null) return null;
    final raw = _cache.store.read(_inboxKey(uid))?.data;
    return raw == null ? null : _tryDecode(() => _decodeInbox(raw));
  }

  /// Persists the live (Realtime-patched) inbox when the screen closes.
  Future<void> saveInbox(List<ConversationSummary> items) async {
    final uid = currentUserId;
    if (uid == null || items.isEmpty) return;
    await _cache.store.write(_inboxKey(uid), _encodeInbox(items.take(pageSize).toList()), _offlinePolicy.ttl);
  }

  static Object? _encodeInbox(List<ConversationSummary> l) => [for (final c in l) c.toJson()];
  static List<ConversationSummary> _decodeInbox(Object? j) => [
    for (final e in (j! as List)) ConversationSummary.fromJson(Map<String, dynamic>.from(e as Map)),
  ];

  /// Last known header data (instant paint / offline).
  ConversationDetail? cachedConversation(String id) {
    final raw = _cache.store.read('chat:conversation:$id')?.data;
    return raw == null ? null : _tryDecode(() => ConversationDetail.fromJson(Map<String, dynamic>.from(raw as Map)));
  }

  /// Header data (members with read state); persisted for offline.
  Future<ConversationDetail> fetchConversation(String id, {bool force = false}) async {
    final detail = await _cache.get<ConversationDetail?>(
      'chat:conversation:$id',
      forceRefresh: force,
      fetch: () async {
        final row = await guard(
          () => _client.from('conversations').select(ConversationDetail.columns).eq('id', id).maybeSingle(),
        );
        return row == null ? null : ConversationDetail.fromJson(row);
      },
      encode: (d) => d?.toJson(),
      decode: (j) => j == null ? null : ConversationDetail.fromJson(Map<String, dynamic>.from(j as Map)),
      policy: const CachePolicy(ttl: Duration(minutes: 1), negativeTtl: Duration(seconds: 10)),
      isEmpty: (d) => d == null,
    );
    return detail ?? (throw const NotFoundFailure('conversation_not_found'));
  }

  Future<String> openDirect(String otherUserId) async {
    final id = await _client.rpcCall<Object?>('get_or_create_direct_conversation', params: {'p_other': otherUserId});
    return '$id';
  }

  Future<String> createGroup(String title, List<String> memberIds) async {
    final id = await _client.rpcCall<Object?>(
      'create_group_conversation',
      params: {'p_title': title.trim(), 'p_members': memberIds},
    );
    return '$id';
  }

  Future<void> markRead(String conversationId) =>
      _client.rpcCall<void>('mark_conversation_read', params: {'p_conversation': conversationId});

  /// Network-first; the last known value is kept for offline/cold start.
  Future<int> unreadConversationsCount() => _cache.get<int>(
    'chat:unread:${_requireUid()}',
    forceRefresh: true,
    fetch: () async {
      final n = await _client.rpcCall<Object?>('get_unread_conversations_count');
      return n is num ? n.toInt() : int.tryParse('$n') ?? 0;
    },
    encode: (n) => n,
    decode: (j) => (j as num?)?.toInt() ?? 0,
    policy: _offlinePolicy,
  );

  int? cachedUnreadCount() {
    final uid = currentUserId;
    final raw = uid == null ? null : _cache.store.read('chat:unread:$uid')?.data;
    return raw is num ? raw.toInt() : null;
  }

  Future<void> setMuted(String conversationId, {required bool muted}) async {
    final uid = _requireUid();
    await guard(
      () => _client
          .from('conversation_members')
          .update({'muted': muted})
          .eq('conversation_id', conversationId)
          .eq('user_id', uid),
    );
    await _cache.invalidate('chat:conversation:$conversationId');
  }

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

  String _messagesKey(String conversationId) => 'chat:messages:$conversationId';

  /// Newest first. [before] pages backwards; [after] catches up after a
  /// reconnect. The latest page (no cursor) is network-first and persisted,
  /// so an opened chat renders offline.
  Future<List<ChatMessage>> fetchMessages(
    String conversationId, {
    DateTime? before,
    DateTime? after,
    int limit = pageSize,
  }) {
    Future<List<ChatMessage>> load() async {
      final rows = await guard(() {
        var q = _client.from('messages').select(ChatMessage.columns).eq('conversation_id', conversationId);
        if (before != null) q = q.lt('created_at', before.toUtc().toIso8601String());
        if (after != null) q = q.gt('created_at', after.toUtc().toIso8601String());
        return q.order('created_at', ascending: false).order('id', ascending: false).limit(limit);
      });
      return rows.map(ChatMessage.fromJson).toList(growable: false);
    }

    if (before != null || after != null) return load();
    return _cache.get<List<ChatMessage>>(
      _messagesKey(conversationId),
      forceRefresh: true,
      fetch: load,
      encode: _encodeMessages,
      decode: _decodeMessages,
      policy: _offlinePolicy,
      isEmpty: (l) => l.isEmpty,
    );
  }

  List<ChatMessage>? cachedMessages(String conversationId) {
    final raw = _cache.store.read(_messagesKey(conversationId))?.data;
    return raw == null ? null : _tryDecode(() => _decodeMessages(raw));
  }

  /// Persists the latest confirmed messages when a thread closes (includes
  /// what arrived over Realtime after the last fetch).
  Future<void> saveMessages(String conversationId, List<ChatMessage> newestFirst) async {
    final confirmed = newestFirst.where((m) => !m.isPending).take(pageSize).toList();
    if (confirmed.isEmpty) return;
    await _cache.store.write(_messagesKey(conversationId), _encodeMessages(confirmed), _offlinePolicy.ttl);
  }

  static Object? _encodeMessages(List<ChatMessage> l) => [for (final m in l) m.toJson()];
  static List<ChatMessage> _decodeMessages(Object? j) => [
    for (final e in (j! as List)) ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)),
  ];

  static T? _tryDecode<T>(T Function() decode) {
    try {
      return decode();
    } on Object {
      return null;
    }
  }

  /// Inserts with the client-generated id (so replays and Realtime echoes
  /// de-duplicate). A duplicate id surfaces as [ConflictFailure].
  Future<ChatMessage> send(ChatMessage draft) async {
    final row = await guard(
      () => _client.from('messages').insert(draft.toInsert()).select(ChatMessage.columns).single(),
    );
    return ChatMessage.fromJson(row);
  }

  /// Soft delete (`deleted_at`): the bubble becomes "message deleted" for all.
  Future<void> softDelete(String messageId) async {
    await guard(
      () =>
          _client.from('messages').update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', messageId),
    );
  }

  /// Uploads an already-compressed WebP to `chat-media/<conversation>/<id>.webp`.
  /// "Already exists" counts as success, so a retry after a lost response
  /// doesn't fail forever.
  Future<String> uploadImage(String conversationId, String fileId, Uint8List webpBytes) async {
    final path = '$conversationId/$fileId.webp';
    try {
      await _client.storage
          .from(AppConstants.chatMediaBucket)
          .uploadBinary(path, webpBytes, fileOptions: const FileOptions(contentType: 'image/webp'));
    } on StorageException catch (e) {
      final duplicate = e.statusCode == '409' || e.message.toLowerCase().contains('exists');
      if (!duplicate) throw AppFailure.from(e);
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
    return path;
  }

  // ---------------------------------------------------------------------------
  // Friends (for starting chats / creating groups)
  // ---------------------------------------------------------------------------

  /// All friends (keyset pages of 100 via `get_friends`), cached and
  /// persisted; an empty list is negatively cached.
  Future<List<UserSummary>> fetchFriends({bool force = false}) {
    final uid = _requireUid();
    return _cache.get<List<UserSummary>>(
      'chat:friends:$uid',
      forceRefresh: force,
      fetch: () async {
        final out = <UserSummary>[];
        String? before;
        for (var page = 0; page < 10; page++) {
          final rows = await _client.rpcList('get_friends', params: {'p_limit': 100, 'p_before': before});
          out.addAll(rows.map(UserSummary.fromJson));
          if (rows.length < 100) break;
          before = rows.last['friends_since']?.toString();
          if (before == null) break;
        }
        return out;
      },
      encode: (list) => [for (final u in list) u.toJson()],
      decode: (j) => [for (final e in (j! as List)) UserSummary.fromJson(Map<String, dynamic>.from(e as Map))],
      policy: const CachePolicy(ttl: Duration(minutes: 5), negativeTtl: Duration(minutes: 1)),
      isEmpty: (list) => list.isEmpty,
    );
  }

  // ---------------------------------------------------------------------------
  // Realtime
  // ---------------------------------------------------------------------------

  RealtimeChannel channel(String topic, {RealtimeChannelConfig opts = const RealtimeChannelConfig()}) =>
      _client.channel(topic, opts: opts);

  /// `UPDATE` on conversations the user belongs to (RLS filters rows), which
  /// fires for every new message thanks to the `last_message_*` trigger.
  RealtimeChannel subscribeConversationUpdates(
    String uid, {
    required void Function(Map<String, dynamic> row) onUpdate,
    required void Function() onResubscribed,
  }) {
    var joins = 0;
    return _client
        .channel('chat-inbox:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'conversations',
          callback: (p) => onUpdate(p.newRecord),
        )
        .subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.subscribed && joins++ > 0) onResubscribed();
        });
  }

  Future<void> removeChannel(RealtimeChannel channel) async {
    try {
      await _client.removeChannel(channel);
    } on Object {
      // Already closed (e.g. socket gone) — nothing to clean up.
    }
  }
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final repo = ChatRepository(ref.watch(supabaseProvider), ref.watch(cachedFetcherProvider))
    ..registerQueueHandlers(ref.watch(offlineQueueProvider));
  ref.onDispose(repo.dispose);
  return repo;
});
