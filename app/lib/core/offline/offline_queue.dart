import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:uuid/uuid.dart';

/// One pending write, persisted until it succeeds.
@immutable
class QueuedOp {
  const QueuedOp({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
  });

  factory QueuedOp.fromJson(Map<String, dynamic> j) => QueuedOp(
    id: j['id'] as String,
    type: j['type'] as String,
    payload: Map<String, dynamic>.from(j['payload'] as Map),
    createdAt: DateTime.parse(j['createdAt'] as String),
    attempts: (j['attempts'] as num?)?.toInt() ?? 0,
  );

  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attempts;

  QueuedOp retried() => QueuedOp(id: id, type: type, payload: payload, createdAt: createdAt, attempts: attempts + 1);

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'payload': payload,
    'createdAt': createdAt.toIso8601String(),
    'attempts': attempts,
  };
}

/// Executes one queued operation. Throw to retry later; return normally on
/// success. Throwing a non-network [AppFailure] (e.g. 403/404/409) drops the
/// op — retrying would never succeed.
typedef QueueHandler = Future<void> Function(Map<String, dynamic> payload);

/// Persistent outbox for writes made while offline (posts, comments,
/// reactions, chat messages, practice answers, exam submissions, routine
/// check-offs…).
///
/// * FIFO per queue, persisted in Hive → survives app restarts.
/// * Flushed when connectivity returns, on app start and on demand.
/// * Exponential backoff (2^attempts s, max 5 min) for transient failures.
/// * Idempotency is the handler's job: use client-generated ids (UUIDs) so a
///   replay after a lost response doesn't create duplicates.
class OfflineQueue {
  OfflineQueue._();
  static final instance = OfflineQueue._();

  static const _boxName = 'prostuti_outbox_v1';
  static const _uuid = Uuid();

  Box<String>? _box;
  final _handlers = <String, QueueHandler>{};
  final _pending = ValueNotifier<int>(0);
  bool _flushing = false;
  bool _flushAgain = false;
  Timer? _retryTimer;
  StreamSubscription<bool>? _connectivitySub;

  /// Number of operations waiting to be synced.
  ValueListenable<int> get pendingCount => _pending;

  Future<void> init() async {
    if (_box != null) return;
    _box = await Hive.openBox<String>(_boxName);
    _pending.value = _box!.length;
    _connectivitySub = ConnectivityService.instance.changes.listen((online) {
      if (online) unawaited(flush());
    });
  }

  /// Registers the executor for an operation type (call once per feature,
  /// e.g. from the repository provider).
  void register(String type, QueueHandler handler) {
    _handlers[type] = handler;
    if (_box != null && _box!.isNotEmpty) unawaited(flush());
  }

  /// Runs [type] now when online; queues it when offline or when the attempt
  /// fails with a network error. Returns true if it already executed.
  Future<bool> run(String type, Map<String, dynamic> payload, {String? id}) async {
    final op = QueuedOp(id: id ?? _uuid.v4(), type: type, payload: payload, createdAt: DateTime.now());
    final handler = _handlers[type];
    if (handler != null && ConnectivityService.instance.isOnline && (_box?.isEmpty ?? true)) {
      try {
        await handler(payload);
        return true;
      } on Object catch (e) {
        if (AppFailure.from(e) is! NetworkFailure) rethrow;
        ConnectivityService.instance.reportFailure();
      }
    }
    await _enqueue(op);
    // Online with a backlog: keep FIFO order by letting flush() run it.
    if (ConnectivityService.instance.isOnline) unawaited(flush());
    return false;
  }

  Future<void> _enqueue(QueuedOp op) async {
    final box = _box;
    if (box == null) throw StateError('OfflineQueue.init() not called');
    // Keys are time-ordered so Hive iteration preserves FIFO order.
    await box.put(
      '${op.createdAt.microsecondsSinceEpoch.toString().padLeft(20, '0')}_${op.id}',
      jsonEncode(op.toJson()),
    );
    _pending.value = box.length;
  }

  /// Ops of [type] still waiting (e.g. to render "sending…" chat bubbles).
  List<QueuedOp> pendingOf(String type) {
    final box = _box;
    if (box == null) return const [];
    return box.values
        .map((v) => QueuedOp.fromJson(jsonDecode(v) as Map<String, dynamic>))
        .where((op) => op.type == type)
        .toList();
  }

  /// Replays queued operations in order. Stops at the first network failure
  /// and schedules a backoff retry.
  Future<void> flush() async {
    final box = _box;
    if (box == null || box.isEmpty) return;
    if (_flushing) {
      _flushAgain = true; // ops added mid-flush are picked up by another pass
      return;
    }
    _flushing = true;
    try {
      do {
        _flushAgain = false;
        if (!await _flushOnce(box)) break;
      } while (_flushAgain && box.isNotEmpty);
    } finally {
      _pending.value = box.length;
      _flushing = false;
    }
  }

  /// One pass over the current keys. Returns false when it stopped early
  /// (network failure → retry scheduled).
  Future<bool> _flushOnce(Box<String> box) async {
    {
      for (final key in box.keys.toList()) {
        final raw = box.get(key);
        if (raw == null) continue;
        final op = QueuedOp.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        final handler = _handlers[op.type];
        if (handler == null) continue; // feature not loaded yet; keep it
        try {
          await handler(op.payload);
          await box.delete(key);
          ConnectivityService.instance.reportSuccess();
        } on Object catch (e) {
          final failure = AppFailure.from(e);
          if (failure is NetworkFailure ||
              failure is RateLimitFailure ||
              (failure is ServerFailure && op.attempts < 5)) {
            await box.put(key, jsonEncode(op.retried().toJson()));
            if (failure is NetworkFailure) ConnectivityService.instance.reportFailure();
            _scheduleRetry(op.attempts + 1);
            _pending.value = box.length;
            return false;
          }
          debugPrint('OfflineQueue: dropping ${op.type} (${failure.code})');
          await box.delete(key);
        }
        _pending.value = box.length;
      }
    }
    return true;
  }

  void _scheduleRetry(int attempts) {
    _retryTimer?.cancel();
    final seconds = (1 << attempts.clamp(0, 8)).clamp(2, 300);
    _retryTimer = Timer(Duration(seconds: seconds), () => unawaited(flush()));
  }

  Future<void> clear() async {
    await _box?.clear();
    _pending.value = 0;
  }

  @visibleForTesting
  Future<void> dispose() async {
    _retryTimer?.cancel();
    await _connectivitySub?.cancel();
  }
}

final offlineQueueProvider = Provider<OfflineQueue>((ref) => OfflineQueue.instance);

/// Pending-sync count for UI badges.
final pendingSyncCountProvider = StreamProvider<int>((ref) {
  final queue = OfflineQueue.instance;
  final controller = StreamController<int>();
  void emit() => controller.add(queue.pendingCount.value);
  queue.pendingCount.addListener(emit);
  emit();
  ref.onDispose(() {
    queue.pendingCount.removeListener(emit);
    unawaited(controller.close());
  });
  return controller.stream;
});
