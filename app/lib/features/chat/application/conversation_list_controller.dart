import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/pagination/paged_notifier.dart';
import 'package:prostuti/core/pagination/paged_state.dart';
import 'package:prostuti/features/chat/application/chat_inbox_events.dart';
import 'package:prostuti/features/chat/application/chat_logic.dart';
import 'package:prostuti/features/chat/data/chat_models.dart';
import 'package:prostuti/features/chat/data/chat_repository.dart';
import 'package:prostuti/features/profile/data/profile.dart';

typedef InboxState = PagedState<ConversationSummary, DateTime>;

/// The chat inbox: keyset pages of `get_conversations` (cursor =
/// `last_message_at`), first page painted from disk cache, and kept live by
/// patching tiles from Realtime rows instead of refetching.
class ConversationListNotifier extends PagedNotifier<ConversationSummary, DateTime> {
  Timer? _refreshTimer;
  String? _uid;
  List<ConversationSummary> _latest = const [];

  ChatRepository get _repo => ref.read(chatRepositoryProvider);

  @override
  InboxState build() {
    _uid = ref.watch(currentUserIdProvider);
    final repo = ref.watch(chatRepositoryProvider);
    final sub = ref.watch(chatInboxEventsProvider).listen(_onEvent);
    listenSelf((_, next) => _latest = next.items);
    ref.onDispose(() {
      unawaited(sub.cancel());
      _refreshTimer?.cancel();
      // Keep the Realtime-patched inbox for the next (possibly offline) open.
      unawaited(repo.saveInbox(_latest));
    });
    return super.build();
  }

  @override
  Future<PageResult<ConversationSummary, DateTime>> fetchPage(DateTime? cursor) async {
    final items = await _repo.fetchConversations(before: cursor);
    final next = items.length < ChatRepository.pageSize ? null : items.last.lastMessageAt;
    return PageResult(items, next);
  }

  @override
  Object idOf(ConversationSummary item) => item.id;

  @override
  List<ConversationSummary>? readCachedFirstPage() => _uid == null ? null : _repo.cachedInbox();

  void _onEvent(InboxEvent event) {
    if (!ref.mounted) return;
    switch (event) {
      case InboxResync():
        _scheduleRefresh();
      case InboxRowUpdated(:final row):
        final next = applyConversationUpdate(
          state.items,
          row,
          myId: _uid,
          activeConversationId: ref.read(activeConversationProvider).id,
        );
        if (next == null) {
          // A conversation we haven't loaded (brand new chat, or beyond the
          // loaded pages) became active → it belongs at the top.
          if (row['last_message_at'] != null) _scheduleRefresh();
          return;
        }
        state = state.copyWith(items: next);
    }
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 400), () => unawaited(refresh()));
  }

  void markReadLocally(String conversationId) => _patch(conversationId, (c) => c.copyWith(unreadCount: 0));

  void setMutedLocally(String conversationId, {required bool muted}) =>
      _patch(conversationId, (c) => c.copyWith(muted: muted));

  void _patch(String id, ConversationSummary Function(ConversationSummary c) update) {
    if (!state.items.any((c) => c.id == id)) return;
    state = state.copyWith(
      items: [
        for (final c in state.items)
          if (c.id == id) update(c) else c,
      ],
    );
  }

  /// Mute/unmute from the inbox (optimistic; reverted on failure).
  Future<void> toggleMute(ConversationSummary c) async {
    setMutedLocally(c.id, muted: !c.muted);
    try {
      await _repo.setMuted(c.id, muted: !c.muted);
    } on Object {
      if (ref.mounted) setMutedLocally(c.id, muted: c.muted);
      rethrow;
    }
  }
}

final conversationListProvider = NotifierProvider.autoDispose<ConversationListNotifier, InboxState>(
  ConversationListNotifier.new,
);

/// Friends to start a chat with / add to a group (cached 2 min).
final chatFriendsProvider = FutureProvider.autoDispose<List<UserSummary>>(
  (ref) => ref.watch(chatRepositoryProvider).fetchFriends(),
);
