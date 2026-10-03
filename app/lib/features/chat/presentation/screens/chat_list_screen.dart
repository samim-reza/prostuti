import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/rate_limit/debouncer.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/paged_list_view.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/chat/application/chat_logic.dart';
import 'package:prostuti/features/chat/application/conversation_list_controller.dart';
import 'package:prostuti/features/chat/data/chat_models.dart';
import 'package:prostuti/features/chat/presentation/widgets/chat_errors.dart';
import 'package:prostuti/features/chat/presentation/widgets/chat_format.dart';
import 'package:prostuti/features/chat/presentation/widgets/conversation_tile.dart';
import 'package:prostuti/features/chat/presentation/widgets/start_chat_sheet.dart';

/// The chat inbox: live conversation list with local search.
class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  final _search = TextEditingController();
  final _debouncer = Debouncer(const Duration(milliseconds: 200));
  bool _searching = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    registerChatFailureMessages();
  }

  @override
  void dispose() {
    _search.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _search.clear();
        _query = '';
      }
    });
  }

  Future<void> _showTileMenu(ConversationSummary c) async {
    final l = context.l10n;
    final action = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListTile(
          leading: Icon(c.muted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined),
          title: Text(c.muted ? l.chatUnmute : l.chatMute),
          onTap: () => Navigator.pop(ctx, true),
        ),
      ),
    );
    if (action != true || !mounted) return;
    try {
      await ref.read(conversationListProvider.notifier).toggleMute(c);
      if (mounted) showInfoSnack(context, c.muted ? l.chatUnmutedSnack : l.chatMutedSnack);
    } on Object catch (e) {
      if (mounted) showChatError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final state = ref.watch(conversationListProvider);
    final notifier = ref.read(conversationListProvider.notifier);
    final myId = ref.watch(currentUserIdProvider);
    final filtered = _query.isEmpty
        ? state
        : state.copyWith(items: filterConversations(state.items, _query, nameOf: (c) => conversationTitle(l, c)));

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: l.chatSearchHint,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
                onChanged: (v) => _debouncer(() {
                  if (mounted) setState(() => _query = v);
                }),
              )
            : Text(l.chatTitle),
        actions: [
          IconButton(
            tooltip: _searching ? l.chatCloseSearchTooltip : l.chatSearchTooltip,
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: _toggleSearch,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: l.chatNewMessageTooltip,
        onPressed: () => unawaited(showStartChatSheet(context)),
        child: const Icon(Icons.edit_square),
      ),
      body: PagedListView<ConversationSummary>(
        state: filtered,
        padding: const EdgeInsets.only(top: Gap.xs, bottom: 96),
        onLoadMore: () => unawaited(notifier.loadMore()),
        onRefresh: notifier.refresh,
        onRetry: () => unawaited(notifier.retry()),
        separator: const Divider(height: 1, indent: 82, endIndent: Gap.lg),
        empty: _query.isNotEmpty
            ? EmptyView(icon: Icons.search_off_rounded, title: l.chatSearchEmpty)
            : EmptyView(
                icon: Icons.forum_outlined,
                title: l.chatEmptyTitle,
                message: l.chatEmptyMessage,
                actionLabel: l.chatEmptyAction,
                action: () => unawaited(showStartChatSheet(context)),
              ),
        itemBuilder: (context, c, _) => ConversationTile(
          key: ValueKey(c.id),
          conversation: c,
          myId: myId,
          onTap: () => context.push(Routes.chat(c.id)),
          onLongPress: () => unawaited(_showTileMenu(c)),
        ),
      ),
    );
  }
}
