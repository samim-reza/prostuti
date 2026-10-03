import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/features/chat/data/realtime_gate.dart';
import 'package:prostuti/features/notifications/data/app_notification.dart';
import 'package:prostuti/features/notifications/data/notifications_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@immutable
sealed class NotificationEvent {
  const NotificationEvent();
}

final class NotificationInserted extends NotificationEvent {
  const NotificationInserted(this.notification);
  final AppNotification notification;
}

/// A row changed elsewhere (e.g. marked read on another device).
final class NotificationUpdated extends NotificationEvent {
  const NotificationUpdated(this.notification);
  final AppNotification notification;
}

/// Back online / re-joined: refetch.
final class NotificationsResync extends NotificationEvent {
  const NotificationsResync();
}

/// ONE Realtime channel per session (`notifications:<uid>`, rows filtered by
/// `user_id=eq.<uid>`), shared by the inbox screen and the bell badge.
/// Opened only while online; removed on sign-out / container dispose.
final notificationEventsProvider = Provider<Stream<NotificationEvent>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  final controller = StreamController<NotificationEvent>.broadcast();
  void emit(NotificationEvent e) {
    if (!controller.isClosed) controller.add(e);
  }

  if (uid != null) {
    final repo = ref.watch(notificationsRepositoryProvider);
    RealtimeChannel? channel;
    final cancel = connectWhenOnline(
      connect: () => channel = repo.subscribe(
        uid,
        onChange: (event, row) {
          if (row.isEmpty) return;
          final n = AppNotification.fromJson(row);
          emit(event == PostgresChangeEvent.insert ? NotificationInserted(n) : NotificationUpdated(n));
        },
        onResubscribed: () => emit(const NotificationsResync()),
      ),
      onReconnect: () => emit(const NotificationsResync()),
    );
    ref.onDispose(() {
      cancel();
      final c = channel;
      if (c != null) unawaited(repo.removeChannel(c));
    });
  }
  ref.onDispose(controller.close);
  return controller.stream;
});
