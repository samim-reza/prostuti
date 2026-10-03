import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:prostuti/core/cache/cache_store.dart';
import 'package:prostuti/core/cache/cached_fetcher.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/offline/offline_queue.dart';
import 'package:prostuti/features/chat/application/chat_thread_controller.dart';
import 'package:prostuti/features/chat/data/chat_models.dart';
import 'package:prostuti/features/chat/data/chat_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _conv = 'conv-1';
const _me = 'me';

/// Records postgres_changes callbacks instead of opening a socket.
class _FakeChannel extends RealtimeChannel {
  _FakeChannel(RealtimeClient socket) : super('realtime:test', socket);

  final callbacks = <PostgresChangeEvent, void Function(PostgresChangePayload)>{};

  @override
  RealtimeChannel onPostgresChanges({
    required PostgresChangeEvent event,
    required void Function(PostgresChangePayload payload) callback,
    String? schema,
    String? table,
    PostgresChangeFilter? filter,
    List<PostgresChangeFilter>? filters,
    List<String>? select,
  }) {
    callbacks[event] = callback;
    return this;
  }

  @override
  RealtimeChannel subscribe([void Function(RealtimeSubscribeStatus, Object?)? callback, Duration? timeout]) => this;

  @override
  Future<String> unsubscribe([Duration? timeout]) async => 'ok';

  void emit(PostgresChangeEvent event, Map<String, dynamic> row) => callbacks[event]?.call(
    PostgresChangePayload(
      schema: 'public',
      table: 'messages',
      commitTimestamp: DateTime.now(),
      eventType: event,
      newRecord: row,
      oldRecord: const {},
      errors: null,
    ),
  );
}

class _FakeRepo extends ChatRepository {
  _FakeRepo(super._client, super._cache, this.socket);

  final RealtimeClient socket;
  final channels = <_FakeChannel>[];
  final sent = <ChatMessage>[];
  List<ChatMessage> serverPage = const [];
  int markReads = 0;

  @override
  String? get currentUserId => _me;

  @override
  Future<List<ChatMessage>> fetchMessages(
    String conversationId, {
    DateTime? before,
    DateTime? after,
    int limit = 30,
  }) async => before == null && after == null ? serverPage : const [];

  @override
  List<ChatMessage>? cachedMessages(String conversationId) => null;

  @override
  Future<void> saveMessages(String conversationId, List<ChatMessage> newestFirst) async {}

  @override
  Future<ChatMessage> send(ChatMessage draft) async {
    sent.add(draft);
    return draft.copyWith(status: MessageStatus.sent, createdAt: draft.createdAt.add(const Duration(seconds: 1)));
  }

  @override
  Future<void> markRead(String conversationId) async => markReads++;

  @override
  RealtimeChannel channel(String topic, {RealtimeChannelConfig opts = const RealtimeChannelConfig()}) {
    final c = _FakeChannel(socket);
    channels.add(c);
    return c;
  }

  @override
  Future<void> removeChannel(RealtimeChannel channel) async {}
}

Map<String, dynamic> _row(ChatMessage m) => {...m.toJson(), 'created_at': m.createdAt.toUtc().toIso8601String()};

void main() {
  late _FakeRepo repo;
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('chat_notifier_test');
    Hive.init(dir.path);
    await OfflineQueue.instance.init();
  });

  tearDownAll(() async {
    await OfflineQueue.instance.dispose();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  setUp(() async {
    await OfflineQueue.instance.clear();
    ConnectivityService.instance.reportSuccess();
    final store = await CacheStore.inMemory();
    repo = _FakeRepo(
      SupabaseClient('http://127.0.0.1:9', 'anon-key', authOptions: const AuthClientOptions(autoRefreshToken: false)),
      CachedFetcher(store),
      RealtimeClient('ws://127.0.0.1:9/realtime/v1'),
    )..registerQueueHandlers(OfflineQueue.instance);
  });

  tearDown(() async {
    repo.dispose();
    ConnectivityService.instance.reportSuccess();
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [currentUserIdProvider.overrideWith((ref) => _me), chatRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<ProviderSubscription<MessagesState>> open(ProviderContainer c) async {
    final sub = c.listen(chatMessagesProvider(_conv), (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return sub;
  }

  test('optimistic send → insert response → Realtime echo: one bubble, sent', () async {
    final c = container();
    final sub = await open(c);
    final notifier = c.read(chatMessagesProvider(_conv).notifier);

    final sending = notifier.sendText('  আসসালামু আলাইকুম  ');
    // Optimistic bubble is visible immediately.
    expect(sub.read().items.single.status, MessageStatus.sending);
    expect(sub.read().items.single.body, 'আসসালামু আলাইকুম');
    await sending;

    final delivered = sub.read().items.single;
    expect(delivered.status, MessageStatus.sent);
    expect(repo.sent.single.id, delivered.id);

    // The Realtime echo of the same row must not duplicate it.
    repo.channels.single.emit(PostgresChangeEvent.insert, _row(delivered));
    await Future<void>.delayed(Duration.zero);
    expect(sub.read().items, hasLength(1));
  });

  test('incoming Realtime messages are merged in order and mark the chat read', () async {
    final base = DateTime.utc(2026, 10, 4, 6);
    repo.serverPage = [ChatMessage(id: 'm1', conversationId: _conv, senderId: 'other', createdAt: base, body: 'প্রথম')];
    final c = container();
    final sub = await open(c);
    expect(sub.read().items.single.id, 'm1');

    final incoming = ChatMessage(
      id: 'm2',
      conversationId: _conv,
      senderId: 'other',
      createdAt: base.add(const Duration(minutes: 1)),
      body: 'দ্বিতীয়',
    );
    repo.channels.single.emit(PostgresChangeEvent.insert, _row(incoming));
    // Soft delete of m1 arrives as an UPDATE.
    repo.channels.single.emit(PostgresChangeEvent.update, {
      ..._row(repo.serverPage.first),
      'deleted_at': base.add(const Duration(minutes: 2)).toIso8601String(),
    });
    await Future<void>.delayed(const Duration(milliseconds: 600));

    expect([for (final m in sub.read().items) m.id], ['m2', 'm1']);
    expect(sub.read().items.last.isDeleted, isTrue);
    expect(repo.markReads, greaterThanOrEqualTo(1));
  });

  test('offline: queued send stays "sending", survives a restart, delivers on reconnect', () async {
    ConnectivityService.instance.reportFailure();
    var c = container();
    var sub = await open(c);
    await c.read(chatMessagesProvider(_conv).notifier).sendText('অফলাইন বার্তা');
    expect(sub.read().items.single.status, MessageStatus.sending);
    expect(repo.sent, isEmpty);
    expect(OfflineQueue.instance.pendingOf(ChatRepository.sendOp), hasLength(1));

    // "Restart": a fresh container restores the pending bubble from the outbox.
    sub.close();
    c.dispose();
    c = container();
    sub = await open(c);
    final restored = sub.read().items.single;
    expect(restored.status, MessageStatus.sending);
    expect(restored.body, 'অফলাইন বার্তা');

    // Back online → the outbox replays → bubble flips to sent (same id).
    ConnectivityService.instance.reportSuccess();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(repo.sent.single.id, restored.id);
    expect(sub.read().items.single.status, MessageStatus.sent);
    expect(OfflineQueue.instance.pendingOf(ChatRepository.sendOp), isEmpty);
  });
}
