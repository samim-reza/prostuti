import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/features/chat/application/chat_inbox_events.dart';
import 'package:prostuti/features/chat/data/chat_repository.dart';

/// Number of conversations with unread messages (badge on `ChatButton` and
/// anywhere else that wants it). `0` while loading / signed out.
///
/// Cheap by design: one `get_unread_conversations_count` call up front, then
/// the shared inbox Realtime channel triggers a *debounced* recount, so a
/// burst of 20 messages costs one tiny query, not 20.
class UnreadChatsCountNotifier extends Notifier<int> {
  static const _debounce = Duration(milliseconds: 700);
  Timer? _timer;

  @override
  int build() {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return 0;
    final sub = ref.watch(chatInboxEventsProvider).listen((_) => _schedule());
    ref.onDispose(() {
      unawaited(sub.cancel());
      _timer?.cancel();
    });
    unawaited(Future.microtask(refresh));
    return ref.read(chatRepositoryProvider).cachedUnreadCount() ?? 0;
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(_debounce, () => unawaited(refresh()));
  }

  /// Re-reads the count (called after a conversation is marked read).
  Future<void> refresh() async {
    try {
      final n = await ref.read(chatRepositoryProvider).unreadConversationsCount();
      if (ref.mounted) state = n;
    } on Object {
      // Keep the last known count; the next event retries.
    }
  }
}

final unreadChatsCountProvider = NotifierProvider<UnreadChatsCountNotifier, int>(UnreadChatsCountNotifier.new);
