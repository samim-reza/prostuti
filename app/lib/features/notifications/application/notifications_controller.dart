import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/offline/offline_queue.dart';
import 'package:prostuti/core/pagination/paged_notifier.dart';
import 'package:prostuti/core/pagination/paged_state.dart';
import 'package:prostuti/features/notifications/application/notification_events.dart';
import 'package:prostuti/features/notifications/application/unread_notifications_count_provider.dart';
import 'package:prostuti/features/notifications/data/app_notification.dart';
import 'package:prostuti/features/notifications/data/notifications_repository.dart';

typedef NotificationsState = PagedState<AppNotification, NotificationCursor>;

/// Applies read/delete actions still waiting in the offline outbox, so a
/// refresh (or a cold start from cache) never resurrects them.
List<AppNotification> applyPendingActions(
  List<AppNotification> items, {
  required Set<int> readIds,
  required Set<int> deletedIds,
  required bool allRead,
  DateTime? now,
}) {
  if (readIds.isEmpty && deletedIds.isEmpty && !allRead) return items;
  final at = now ?? DateTime.now().toUtc();
  return [
    for (final n in items)
      if (!deletedIds.contains(n.id))
        if (!n.isRead && (allRead || readIds.contains(n.id))) n.copyWith(readAt: at) else n,
  ];
}

/// The notification inbox: keyset pages by `(created_at, id)`, first page
/// cached for offline, Realtime inserts prepended, optimistic (and queued)
/// mark-read / mark-all / delete.
class NotificationsNotifier extends PagedNotifier<AppNotification, NotificationCursor> {
  List<AppNotification> _latest = const [];

  NotificationsRepository get _repo => ref.read(notificationsRepositoryProvider);
  OfflineQueue get _queue => ref.read(offlineQueueProvider);

  @override
  NotificationsState build() {
    ref.watch(currentUserIdProvider);
    final repo = ref.watch(notificationsRepositoryProvider);
    final sub = ref.watch(notificationEventsProvider).listen(_onEvent);
    listenSelf((_, next) => _latest = next.items);
    ref.onDispose(() {
      unawaited(sub.cancel());
      unawaited(repo.saveFirstPage(_latest));
    });
    return super.build();
  }

  @override
  Future<PageResult<AppNotification, NotificationCursor>> fetchPage(NotificationCursor? cursor) async {
    final raw = await _repo.fetchPage(before: cursor);
    // Cursor from the raw page: locally hidden (pending-delete) rows must not
    // end the pagination early.
    final next = raw.length < NotificationsRepository.pageSize ? null : raw.last.cursor;
    return PageResult(_withPending(raw), next);
  }

  @override
  Object idOf(AppNotification item) => item.id;

  @override
  List<AppNotification>? readCachedFirstPage() {
    final cached = _repo.cachedFirstPage();
    return cached == null ? null : _withPending(cached);
  }

  List<AppNotification> _withPending(List<AppNotification> items) {
    int? idOfOp(QueuedOp op) => (op.payload['id'] as num?)?.toInt();
    return applyPendingActions(
      items,
      readIds: {for (final op in _queue.pendingOf(NotificationsRepository.markReadOp)) ?idOfOp(op)},
      deletedIds: {for (final op in _queue.pendingOf(NotificationsRepository.deleteOp)) ?idOfOp(op)},
      allRead: _queue.pendingOf(NotificationsRepository.markAllReadOp).isNotEmpty,
    );
  }

  void _onEvent(NotificationEvent e) {
    if (!ref.mounted) return;
    switch (e) {
      case NotificationInserted(:final notification):
        upsertFirst(notification);
      case NotificationUpdated(:final notification):
        if (state.items.any((n) => n.id == notification.id)) replace(notification);
      case NotificationsResync():
        unawaited(refresh());
    }
  }

  /// Runs now when online, else queues; if it was queued behind other
  /// pending work while online, nudge the outbox so it isn't left waiting.
  Future<void> _run(String type, Map<String, dynamic> payload) async {
    final done = await _queue.run(type, payload);
    if (!done && ConnectivityService.instance.isOnline) unawaited(_queue.flush());
  }

  UnreadNotificationsCountNotifier? get _count =>
      ref.exists(unreadNotificationsCountProvider) ? ref.read(unreadNotificationsCountProvider.notifier) : null;

  /// Optimistic; queued when offline. Never throws (reverted on refusal).
  Future<void> markRead(AppNotification n) async {
    if (n.isRead) return;
    replace(n.copyWith(readAt: DateTime.now().toUtc()));
    _count?.adjust(-1);
    try {
      await _run(NotificationsRepository.markReadOp, {'id': n.id});
    } on Object {
      if (!ref.mounted) return;
      replace(n);
      _count?.adjust(1);
    }
  }

  Future<void> markAllRead() async {
    final before = state.items;
    final now = DateTime.now().toUtc();
    state = state.copyWith(
      items: [
        for (final n in before)
          if (n.isRead) n else n.copyWith(readAt: now),
      ],
    );
    _count?.clear();
    try {
      await _run(NotificationsRepository.markAllReadOp, const {});
    } on Object catch (e) {
      if (ref.mounted) state = state.copyWith(items: before);
      unawaited(_count?.refresh());
      throw AppFailure.from(e);
    }
  }

  /// Optimistic delete (swipe); restored in place if the server refuses.
  Future<void> delete(AppNotification n) async {
    final index = state.items.indexWhere((x) => x.id == n.id);
    if (index < 0) return;
    removeWhere((x) => x.id == n.id);
    if (!n.isRead) _count?.adjust(-1);
    try {
      await _run(NotificationsRepository.deleteOp, {'id': n.id});
    } on Object catch (e) {
      if (ref.mounted) {
        final items = [...state.items]..insert(index.clamp(0, state.items.length), n);
        state = state.copyWith(items: items);
        if (!n.isRead) _count?.adjust(1);
      }
      throw AppFailure.from(e);
    }
  }
}

final notificationsProvider = NotifierProvider.autoDispose<NotificationsNotifier, NotificationsState>(
  NotificationsNotifier.new,
);
