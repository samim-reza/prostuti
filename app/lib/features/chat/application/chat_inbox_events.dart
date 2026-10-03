import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/features/chat/data/chat_repository.dart';
import 'package:prostuti/features/chat/data/realtime_gate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@immutable
sealed class InboxEvent {
  const InboxEvent();
}

/// A `conversations` row changed (new message, renamed group …).
final class InboxRowUpdated extends InboxEvent {
  const InboxRowUpdated(this.row);
  final Map<String, dynamic> row;
}

/// Back online / Realtime re-joined: updates may have been missed → refetch.
final class InboxResync extends InboxEvent {
  const InboxResync();
}

/// ONE Realtime channel per session for inbox activity, shared by the chat
/// list and the unread badge (instead of a channel per widget). It is opened
/// only while online and torn down on sign-out (user id changes) or when
/// the container is disposed.
final chatInboxEventsProvider = Provider<Stream<InboxEvent>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  final controller = StreamController<InboxEvent>.broadcast();
  void emit(InboxEvent e) {
    if (!controller.isClosed) controller.add(e);
  }

  if (uid != null) {
    final repo = ref.watch(chatRepositoryProvider);
    RealtimeChannel? channel;
    final cancel = connectWhenOnline(
      connect: () => channel = repo.subscribeConversationUpdates(
        uid,
        onUpdate: (row) => emit(InboxRowUpdated(row)),
        onResubscribed: () => emit(const InboxResync()),
      ),
      onReconnect: () => emit(const InboxResync()),
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

/// Which conversation is open on screen right now (not reactive on purpose:
/// it is only consulted when events arrive, e.g. to keep its unread at 0).
class ActiveConversation {
  String? id;
}

final activeConversationProvider = Provider<ActiveConversation>((ref) => ActiveConversation());
