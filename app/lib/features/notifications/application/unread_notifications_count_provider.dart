import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/features/notifications/application/notification_events.dart';
import 'package:prostuti/features/notifications/data/notifications_repository.dart';

/// Unread notifications for the bell badge (`0` while loading / signed out;
/// the last known value while offline).
///
/// One count query up front; new rows bump it instantly from Realtime, and
/// read-state changes from elsewhere trigger a debounced recount. Local
/// actions adjust it optimistically via [adjust] / [clear].
class UnreadNotificationsCountNotifier extends Notifier<int> {
  Timer? _timer;

  @override
  int build() {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return 0;
    final sub = ref.watch(notificationEventsProvider).listen((e) {
      switch (e) {
        case NotificationInserted(:final notification):
          if (!notification.isRead) state = state + 1;
        case NotificationUpdated():
        case NotificationsResync():
          _schedule();
      }
    });
    ref.onDispose(() {
      unawaited(sub.cancel());
      _timer?.cancel();
    });
    unawaited(Future.microtask(refresh));
    return ref.read(notificationsRepositoryProvider).cachedUnreadCount() ?? 0;
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 800), () => unawaited(refresh()));
  }

  Future<void> refresh() async {
    try {
      final n = await ref.read(notificationsRepositoryProvider).unreadCount();
      if (ref.mounted) state = n;
    } on Object {
      // Keep the last known value.
    }
  }

  void adjust(int delta) => state = math.max(0, state + delta);

  void clear() => state = 0;
}

final unreadNotificationsCountProvider = NotifierProvider<UnreadNotificationsCountNotifier, int>(
  UnreadNotificationsCountNotifier.new,
);
