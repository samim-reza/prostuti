import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/offline/offline_queue.dart';
import 'package:prostuti/core/pagination/paged_notifier.dart';
import 'package:prostuti/core/pagination/paged_state.dart';
import 'package:prostuti/core/rate_limit/debouncer.dart';
import 'package:prostuti/features/chat/application/chat_inbox_events.dart';
import 'package:prostuti/features/chat/application/chat_logic.dart';
import 'package:prostuti/features/chat/application/chat_room.dart';
import 'package:prostuti/features/chat/application/conversation_list_controller.dart';
import 'package:prostuti/features/chat/application/unread_chats_count_provider.dart';
import 'package:prostuti/features/chat/data/chat_media_urls.dart';
import 'package:prostuti/features/chat/data/chat_models.dart';
import 'package:prostuti/features/chat/data/chat_repository.dart';
import 'package:uuid/uuid.dart';

typedef MessagesState = PagedState<ChatMessage, DateTime>;

/// Messages of one conversation, newest first (rendered by a reversed list).
///
/// * keyset pages of 30 older messages (`created_at < cursor`); the latest
///   page is persisted, so an opened chat renders offline;
/// * text sends go through the [OfflineQueue] with client-generated UUIDs —
///   the optimistic bubble, the insert response, a later replay and the
///   Realtime echo all collapse into one bubble; queued bubbles stay
///   "sending" (also after an app restart) until delivered;
/// * image sends need the network (upload → insert; retry never re-uploads);
/// * marks the conversation read on open and when messages arrive while the
///   screen is visible (debounced, queued when offline), then broadcasts a
///   read receipt.
class ChatMessagesNotifier extends PagedNotifier<ChatMessage, DateTime> {
  ChatMessagesNotifier(this.conversationId);

  final String conversationId;

  static const _uuid = Uuid();

  /// Mirrors the server limit (40 messages / 60 s) for instant feedback.
  final _bucket = TokenBucket(capacity: 40, refillEvery: const Duration(milliseconds: 1500));

  /// Image ids already in storage (a retry must not upload again).
  final _uploaded = <String>{};

  /// Messages sent from this device (survive a refresh until confirmed).
  final _mine = <String, ChatMessage>{};
  final _buffer = <ChatMessage>[];
  List<ChatMessage> _latest = const [];
  bool _refreshing = false;
  bool _foreground = true;
  bool _readPending = false;
  Timer? _readTimer;
  Timer? _resyncTimer;
  String? _uid;

  ChatRepository get _repo => ref.read(chatRepositoryProvider);
  ChatRoomNotifier get _room => ref.read(chatRoomProvider(conversationId).notifier);
  OfflineQueue get _queue => ref.read(offlineQueueProvider);

  @override
  MessagesState build() {
    _uid = ref.watch(currentUserIdProvider);
    final repo = ref.watch(chatRepositoryProvider);
    final room = ref.watch(chatRoomProvider(conversationId).notifier);
    final active = ref.read(activeConversationProvider)..id = conversationId;
    final subs = [
      room.messages.listen(_onRemote),
      room.resyncs.listen((_) => _scheduleResync()),
      repo.outbox.listen(_onOutbox),
    ];
    listenSelf((_, next) => _latest = next.items);
    ref.onDispose(() {
      for (final s in subs) {
        unawaited(s.cancel());
      }
      _readTimer?.cancel();
      _resyncTimer?.cancel();
      if (active.id == conversationId) active.id = null;
      unawaited(repo.saveMessages(conversationId, _latest));
    });

    final initial = super.build();
    // Sends still waiting in the offline outbox (e.g. after a restart).
    _restoreQueued();
    if (_mine.isEmpty) return initial;
    var items = initial.items;
    for (final m in _mine.values) {
      items = mergeMessage(items, m);
    }
    return initial.copyWith(items: items, isLoadingFirst: false);
  }

  void _restoreQueued() {
    for (final op in _queue.pendingOf(ChatRepository.sendOp)) {
      if (op.payload['conversation_id'] != conversationId) continue;
      try {
        final m = ChatMessage.fromQueuePayload(op.payload);
        _mine[m.id] = m;
      } on Object {
        // Malformed payload — ignore.
      }
    }
  }

  @override
  List<ChatMessage>? readCachedFirstPage() => _repo.cachedMessages(conversationId);

  @override
  Future<PageResult<ChatMessage, DateTime>> fetchPage(DateTime? cursor) async {
    final items = await _repo.fetchMessages(conversationId, before: cursor);
    _prefetchMedia(items);
    final next = items.length < ChatRepository.pageSize ? null : items.last.createdAt;
    return PageResult(items, next);
  }

  @override
  Object idOf(ChatMessage item) => item.id;

  @override
  Future<void> refresh() async {
    _refreshing = true;
    try {
      await super.refresh();
    } finally {
      _refreshing = false;
    }
    if (!ref.mounted) return;
    // A refresh replaces the list wholesale: put back what it can't know
    // about yet (unconfirmed sends, Realtime rows that raced the query).
    final extra = [..._buffer, ..._mine.values];
    _buffer.clear();
    if (extra.isEmpty) return;
    var items = state.items;
    for (final m in extra) {
      items = mergeMessage(items, m);
    }
    state = state.copyWith(items: items);
  }

  @override
  void onFirstPageLoaded(List<ChatMessage> items) {
    _readPending = true;
    if (_foreground) _scheduleRead();
  }

  void _prefetchMedia(List<ChatMessage> items) {
    final paths = [
      for (final m in items)
        if (m.isImage && !m.isDeleted && m.mediaPath != null) m.mediaPath!,
    ];
    if (paths.isEmpty || !ConnectivityService.instance.isOnline) return;
    unawaited(ref.read(chatMediaUrlsProvider).prefetch(paths));
  }

  /// Merges a message into the list (and tracks own unconfirmed sends).
  void _put(ChatMessage m) {
    if (!ref.mounted) return;
    if (_refreshing && !m.isPending) _buffer.add(m);
    if (m.senderId == _uid) {
      final prev = _mine[m.id];
      if (!m.isPending) {
        _mine.remove(m.id); // confirmed: the server copy is the truth now
      } else if (prev == null || prev.isPending) {
        _mine[m.id] = m;
      }
    }
    state = state.copyWith(items: mergeMessage(state.items, m));
  }

  void _onRemote(ChatMessage m) {
    if (!ref.mounted) return;
    final isNew = !state.items.any((e) => e.id == m.id);
    _put(m);
    if (m.senderId != _uid) {
      _room.clearTyping(m.senderId);
      if (isNew) {
        if (m.isImage) _prefetchMedia([m]);
        _onIncoming();
      }
    }
  }

  void _onOutbox(OutboxEvent e) {
    switch (e) {
      case MessageDelivered(:final message) when message.conversationId == conversationId:
        _put(message);
      case MessageRejected(:final messageId, :final conversationId) when conversationId == this.conversationId:
        final m = state.items.firstWhereOrNull((x) => x.id == messageId);
        if (m != null && m.isPending) _put(m.copyWith(status: MessageStatus.failed));
      default:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------

  String _requireUid() => _uid ?? (throw const AuthFailure('not_authenticated'));

  void _checkRate() {
    if (!_bucket.tryTake()) throw const RateLimitFailure(action: 'message_send');
  }

  /// Optimistic text send. Works offline: the message is queued and stays
  /// "sending" until the outbox delivers it.
  Future<void> sendText(String text, {String? replyToId}) async {
    final body = text.trim();
    if (body.isEmpty) return;
    _checkRate();
    _room.resetTypingThrottle();
    await _deliverText(
      ChatMessage(
        id: _uuid.v4(),
        conversationId: conversationId,
        senderId: _requireUid(),
        body: body,
        replyToId: replyToId,
        createdAt: DateTime.now().toUtc(),
        status: MessageStatus.sending,
      ),
    );
  }

  Future<void> _deliverText(ChatMessage draft) async {
    _put(draft);
    try {
      // On success the queue handler reports [MessageDelivered] (→ _onOutbox).
      final delivered = await _queue.run(ChatRepository.sendOp, draft.toQueuePayload(), id: draft.id);
      if (!delivered && ConnectivityService.instance.isOnline) unawaited(_queue.flush());
    } on Object catch (e) {
      final failure = AppFailure.from(e);
      if (failure is ConflictFailure) {
        _put(draft.copyWith(status: MessageStatus.sent));
        return;
      }
      _put(draft.copyWith(status: MessageStatus.failed));
      throw failure;
    }
  }

  /// [webpBytes] must already be compressed (MediaService does that).
  /// Images need the network: offline this throws [NetworkFailure] before
  /// anything is shown.
  Future<void> sendImage(Uint8List webpBytes, {String? replyToId}) async {
    if (!ConnectivityService.instance.isOnline) throw const NetworkFailure();
    _checkRate();
    final id = _uuid.v4();
    await _deliverImage(
      ChatMessage(
        id: id,
        conversationId: conversationId,
        senderId: _requireUid(),
        kind: MessageKind.image,
        mediaPath: '$conversationId/$id.webp',
        replyToId: replyToId,
        createdAt: DateTime.now().toUtc(),
        status: MessageStatus.sending,
        localBytes: webpBytes,
      ),
    );
  }

  Future<void> _deliverImage(ChatMessage draft) async {
    _put(draft);
    try {
      if (!_uploaded.contains(draft.id)) {
        final bytes = draft.localBytes;
        if (bytes == null) throw const ValidationFailure('image_missing');
        await _repo.uploadImage(conversationId, draft.id, bytes);
        _uploaded.add(draft.id);
      }
      _put(await _repo.send(draft));
    } on ConflictFailure {
      _put(draft.copyWith(status: MessageStatus.sent));
    } on Object catch (e) {
      _put(draft.copyWith(status: MessageStatus.failed));
      throw AppFailure.from(e);
    }
  }

  Future<void> retrySend(String messageId) async {
    final m = state.items.firstWhereOrNull((e) => e.id == messageId);
    if (m == null || m.status != MessageStatus.failed) return;
    if (m.isImage) {
      if (!ConnectivityService.instance.isOnline) throw const NetworkFailure();
      _checkRate();
      await _deliverImage(m.copyWith(status: MessageStatus.sending));
    } else {
      _checkRate();
      await _deliverText(m.copyWith(status: MessageStatus.sending));
    }
  }

  /// Drops an unsent (failed) message from this device.
  void discard(String messageId) {
    _mine.remove(messageId);
    state = state.copyWith(
      items: [
        for (final m in state.items)
          if (!(m.id == messageId && m.isPending)) m,
      ],
    );
  }

  /// Soft delete for everyone (optimistic; reverted on failure).
  Future<void> deleteMessage(String messageId) async {
    final m = state.items.firstWhereOrNull((e) => e.id == messageId);
    if (m == null || m.senderId != _uid || m.isDeleted) return;
    if (m.status == MessageStatus.failed) return discard(messageId);
    if (m.isPending) return;
    _put(m.copyWith(deletedAt: DateTime.now().toUtc()));
    try {
      await _repo.softDelete(messageId);
    } on Object catch (e) {
      _put(m.copyWith(clearDeletedAt: true));
      throw AppFailure.from(e);
    }
  }

  // ---------------------------------------------------------------------------
  // Read state & reconnects
  // ---------------------------------------------------------------------------

  /// The screen reports whether it is actually visible (app resumed and the
  /// route not covered); reads are only marked while it is.
  void setForeground({required bool visible}) {
    _foreground = visible;
    if (visible && _readPending) _scheduleRead();
  }

  void _onIncoming() {
    _readPending = true;
    if (_foreground) _scheduleRead();
  }

  void _scheduleRead() {
    _readTimer?.cancel();
    _readTimer = Timer(const Duration(milliseconds: 400), () => unawaited(_markRead()));
  }

  Future<void> _markRead() async {
    if (!ref.mounted || !_foreground) return;
    _readPending = false;
    final queue = _queue;
    final alreadyQueued = queue
        .pendingOf(ChatRepository.markReadOp)
        .any((op) => op.payload['conversation_id'] == conversationId);
    var delivered = false;
    if (!alreadyQueued) {
      try {
        delivered = await queue.run(ChatRepository.markReadOp, {'conversation_id': conversationId});
      } on Object {
        _readPending = true;
        return;
      }
    }
    if (!ref.mounted) return;
    if (delivered) {
      final newest = newestConfirmed(state.items);
      if (newest != null) _room.broadcastRead(newest.createdAt);
      if (ref.exists(unreadChatsCountProvider)) {
        unawaited(ref.read(unreadChatsCountProvider.notifier).refresh());
      }
    }
    if (ref.exists(conversationListProvider)) {
      ref.read(conversationListProvider.notifier).markReadLocally(conversationId);
    }
  }

  void _scheduleResync() {
    _resyncTimer?.cancel();
    _resyncTimer = Timer(const Duration(milliseconds: 500), () => unawaited(resync()));
  }

  /// Back online / re-joined: refetch the latest page (or, when older pages
  /// are loaded, only what is newer — keeps the scroll position).
  Future<void> resync() async {
    if (!ref.mounted) return;
    final newest = newestConfirmed(state.items);
    if (newest == null || state.items.length <= ChatRepository.pageSize) return refresh();
    try {
      final fresh = await _repo.fetchMessages(conversationId, after: newest.createdAt, limit: 100);
      if (!ref.mounted || fresh.isEmpty) return;
      var items = state.items;
      for (final m in fresh.reversed) {
        items = mergeMessage(items, m);
      }
      state = state.copyWith(items: items);
      _prefetchMedia(fresh);
      if (fresh.any((m) => m.senderId != _uid)) _onIncoming();
    } on Object {
      // The next event or re-open fixes it.
    }
  }
}

final chatMessagesProvider = NotifierProvider.autoDispose.family<ChatMessagesNotifier, MessagesState, String>(
  ChatMessagesNotifier.new,
);

/// Header data + members' read state: cached copy first (instant, offline),
/// then the fresh one; kept current by read receipts.
class ChatConversationNotifier extends AsyncNotifier<ConversationDetail> {
  ChatConversationNotifier(this.conversationId);

  final String conversationId;

  @override
  Future<ConversationDetail> build() async {
    final repo = ref.watch(chatRepositoryProvider);
    final room = ref.watch(chatRoomProvider(conversationId).notifier);
    final subs = [
      room.reads.listen((r) => _bumpRead(r.userId, r.at)),
      // A sender has necessarily read everything up to their own message.
      room.messages.listen((m) => _bumpRead(m.senderId, m.createdAt)),
      room.resyncs.listen((_) => unawaited(_revalidate())),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        unawaited(s.cancel());
      }
    });
    final cached = repo.cachedConversation(conversationId);
    if (cached != null) {
      unawaited(Future.microtask(_revalidate));
      return cached;
    }
    return repo.fetchConversation(conversationId, force: true);
  }

  Future<void> _revalidate() async {
    try {
      final fresh = await ref.read(chatRepositoryProvider).fetchConversation(conversationId, force: true);
      if (ref.mounted) state = AsyncData(fresh);
    } on Object {
      // Keep showing the cached header.
    }
  }

  void _bumpRead(String userId, DateTime at) {
    final detail = state.value;
    if (detail == null || !ref.mounted) return;
    final member = detail.member(userId);
    if (member == null || (member.lastReadAt != null && !at.isAfter(member.lastReadAt!))) return;
    state = AsyncData(
      detail.copyWith(
        members: [
          for (final m in detail.members)
            if (m.userId == userId) m.copyWith(lastReadAt: at) else m,
        ],
      ),
    );
  }

  Future<void> setMuted({required bool muted}) async {
    final detail = state.value;
    final uid = ref.read(currentUserIdProvider);
    if (detail == null || uid == null) return;
    void apply(bool value) {
      if (!ref.mounted) return;
      state = AsyncData(
        detail.copyWith(
          members: [
            for (final m in detail.members)
              if (m.userId == uid) m.copyWith(muted: value) else m,
          ],
        ),
      );
      if (ref.exists(conversationListProvider)) {
        ref.read(conversationListProvider.notifier).setMutedLocally(conversationId, muted: value);
      }
    }

    apply(muted);
    try {
      await ref.read(chatRepositoryProvider).setMuted(conversationId, muted: muted);
    } on Object {
      apply(!muted);
      rethrow;
    }
  }
}

final chatConversationProvider = AsyncNotifierProvider.autoDispose
    .family<ChatConversationNotifier, ConversationDetail, String>(ChatConversationNotifier.new);

/// Everything the message list renders, derived once per change.
@immutable
class ChatThreadView {
  const ChatThreadView({
    required this.entries,
    required this.byId,
    required this.indexById,
    required this.state,
    this.seen,
  });

  final List<TimelineEntry> entries;

  /// Entry index per message id: lets the reversed ListView keep each
  /// bubble's element/state when new messages are inserted at index 0.
  final Map<String, int> indexById;

  /// Loaded messages by id (reply quotes).
  final Map<String, ChatMessage> byId;
  final MessagesState state;
  final SeenInfo? seen;
}

final chatThreadViewProvider = Provider.autoDispose.family<ChatThreadView, String>((ref, conversationId) {
  final state = ref.watch(chatMessagesProvider(conversationId));
  final uid = ref.watch(currentUserIdProvider);
  final members = ref.watch(chatConversationProvider(conversationId).select((a) => a.value?.members));
  final othersRead = <String, DateTime?>{
    for (final m in members ?? const <ChatMember>[])
      if (m.userId != uid) m.userId: m.lastReadAt,
  };
  final entries = buildTimeline(state.items);
  return ChatThreadView(
    entries: entries,
    byId: {for (final m in state.items) m.id: m},
    indexById: {
      for (var i = 0; i < entries.length; i++)
        if (entries[i] case MessageEntry(:final message)) message.id: i,
    },
    state: state,
    seen: uid == null || othersRead.isEmpty ? null : computeSeen(state.items, uid, othersRead),
  );
});
