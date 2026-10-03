import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/features/chat/data/chat_models.dart';
import 'package:prostuti/features/chat/data/chat_repository.dart';
import 'package:prostuti/features/chat/data/realtime_gate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Who else is in the open conversation right now.
@immutable
class ChatRoomState {
  const ChatRoomState({this.online = const {}, this.typing = const {}});

  /// Other members with the conversation open (Realtime presence).
  final Set<String> online;

  /// Other members currently typing (broadcast, auto-expires).
  final Set<String> typing;

  static const _eq = SetEquality<String>();

  @override
  bool operator ==(Object other) =>
      other is ChatRoomState && _eq.equals(other.online, online) && _eq.equals(other.typing, typing);

  @override
  int get hashCode => Object.hash(_eq.hash(online), _eq.hash(typing));
}

/// "User X has read everything up to [at]" (broadcast by the reader).
@immutable
class ReadReceipt {
  const ReadReceipt(this.userId, this.at);
  final String userId;
  final DateTime at;
}

/// Leading-edge throttle for typing broadcasts: at most one per [interval].
class TypingThrottle {
  TypingThrottle({this.interval = const Duration(seconds: 2)});
  final Duration interval;
  DateTime? _last;

  bool shouldSend(DateTime now) {
    final last = _last;
    if (last != null && now.difference(last) < interval) return false;
    _last = now;
    return true;
  }

  void reset() => _last = null;
}

/// Owns the single Realtime channel `chat:<conversationId>` of an open chat:
///
/// * postgres_changes INSERT/UPDATE on `messages` (filtered by conversation,
///   RLS-checked) → [messages];
/// * presence (keyed by user id) → [ChatRoomState.online];
/// * broadcast `typing` (throttled to 1 per 2 s, expires after 4 s) and
///   `read` receipts → [ChatRoomState.typing], [reads].
///
/// The channel is removed when the last listener goes away (autoDispose).
class ChatRoomNotifier extends Notifier<ChatRoomState> {
  ChatRoomNotifier(this.conversationId);

  final String conversationId;

  static const typingTimeout = Duration(seconds: 4);

  RealtimeChannel? _channel;
  String? _uid;
  bool _joined = false;
  final _typingThrottle = TypingThrottle();
  final _typingTimers = <String, Timer>{};
  StreamController<ChatMessage> _messages = StreamController<ChatMessage>.broadcast();
  StreamController<ReadReceipt> _reads = StreamController<ReadReceipt>.broadcast();
  StreamController<void> _resyncs = StreamController<void>.broadcast();

  /// Inserted or updated messages of this conversation.
  Stream<ChatMessage> get messages => _messages.stream;

  /// Other members' read receipts.
  Stream<ReadReceipt> get reads => _reads.stream;

  /// Emitted after a reconnect: events may have been missed → catch up.
  Stream<void> get resyncs => _resyncs.stream;

  @override
  ChatRoomState build() {
    _uid = ref.watch(currentUserIdProvider);
    final repo = ref.watch(chatRepositoryProvider);
    if (_messages.isClosed) _messages = StreamController<ChatMessage>.broadcast();
    if (_reads.isClosed) _reads = StreamController<ReadReceipt>.broadcast();
    if (_resyncs.isClosed) _resyncs = StreamController<void>.broadcast();

    final uid = _uid;
    if (uid != null) {
      // Join only while online; every return to online triggers a resync
      // (the thread refetches its latest page).
      final cancel = connectWhenOnline(connect: () => _connect(repo, uid), onReconnect: _emitResync);
      ref.onDispose(() {
        cancel();
        _joined = false;
        final channel = _channel;
        _channel = null;
        if (channel != null) unawaited(repo.removeChannel(channel));
      });
    }
    ref.onDispose(() {
      for (final t in _typingTimers.values) {
        t.cancel();
      }
      _typingTimers.clear();
      unawaited(_messages.close());
      unawaited(_reads.close());
      unawaited(_resyncs.close());
    });
    return const ChatRoomState();
  }

  void _connect(ChatRepository repo, String uid) {
    final filter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'conversation_id',
      value: conversationId,
    );
    var joins = 0;
    final channel = repo
        .channel('chat:$conversationId', opts: RealtimeChannelConfig(key: uid))
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: filter,
          callback: _onRow,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          filter: filter,
          callback: _onRow,
        )
        .onPresenceSync((_) => _syncPresence())
        .onBroadcast(event: 'typing', callback: _onTyping)
        .onBroadcast(event: 'read', callback: _onRead);
    _channel = channel;
    channel.subscribe((status, _) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        _joined = true;
        unawaited(_track());
        // Re-joined after a drop: events may have been missed.
        if (joins++ > 0) _emitResync();
      } else {
        _joined = false;
      }
    });
  }

  void _emitResync() {
    if (!_resyncs.isClosed) _resyncs.add(null);
  }

  Future<void> _track() async {
    try {
      await _channel?.track({'user_id': _uid, 'online_at': DateTime.now().toUtc().toIso8601String()});
    } on Object {
      // Presence is best-effort.
    }
  }

  void _onRow(PostgresChangePayload payload) {
    if (_messages.isClosed || payload.newRecord.isEmpty) return;
    final message = ChatMessage.fromJson(payload.newRecord);
    if (message.conversationId != conversationId) return;
    _messages.add(message);
  }

  void _syncPresence() {
    final channel = _channel;
    if (channel == null || !ref.mounted) return;
    final ids = <String>{};
    for (final s in channel.presenceState()) {
      for (final p in s.presences) {
        final id = p.payload['user_id']?.toString() ?? s.key;
        if (id != _uid) ids.add(id);
      }
    }
    state = ChatRoomState(online: ids, typing: state.typing);
  }

  static Map<String, dynamic> _inner(Map<String, dynamic> p) =>
      p['payload'] is Map ? Map<String, dynamic>.from(p['payload'] as Map) : p;

  void _onTyping(Map<String, dynamic> payload) {
    final userId = _inner(payload)['user_id']?.toString();
    if (userId == null || userId == _uid || !ref.mounted) return;
    _typingTimers[userId]?.cancel();
    _typingTimers[userId] = Timer(typingTimeout, () => clearTyping(userId));
    if (!state.typing.contains(userId)) {
      state = ChatRoomState(online: state.online, typing: {...state.typing, userId});
    }
  }

  void _onRead(Map<String, dynamic> payload) {
    final p = _inner(payload);
    final userId = p['user_id']?.toString();
    final at = DateTime.tryParse('${p['at']}');
    if (userId == null || at == null || userId == _uid || _reads.isClosed) return;
    _reads.add(ReadReceipt(userId, at));
  }

  /// Called when a message from [userId] arrives (they stopped typing).
  void clearTyping(String userId) {
    _typingTimers.remove(userId)?.cancel();
    if (!ref.mounted || !state.typing.contains(userId)) return;
    state = ChatRoomState(online: state.online, typing: {...state.typing}..remove(userId));
  }

  /// Call on every keystroke; broadcasts at most once per 2 seconds.
  void notifyTyping() {
    final channel = _channel;
    if (channel == null || !_joined || !_typingThrottle.shouldSend(DateTime.now())) return;
    unawaited(_send(channel, 'typing', {'user_id': _uid}));
  }

  /// After sending, the next keystroke may announce typing again at once.
  void resetTypingThrottle() => _typingThrottle.reset();

  /// Tells the other members I have read everything up to [upTo] (a server
  /// timestamp, so device clock skew can't fake a receipt).
  void broadcastRead(DateTime upTo) {
    final channel = _channel;
    if (channel == null || !_joined) return;
    unawaited(_send(channel, 'read', {'user_id': _uid, 'at': upTo.toUtc().toIso8601String()}));
  }

  Future<void> _send(RealtimeChannel channel, String event, Map<String, dynamic> payload) async {
    try {
      await channel.sendBroadcastMessage(event: event, payload: payload);
    } on Object {
      // Ephemeral signal; dropping one is harmless.
    }
  }
}

final chatRoomProvider = NotifierProvider.autoDispose.family<ChatRoomNotifier, ChatRoomState, String>(
  ChatRoomNotifier.new,
);
