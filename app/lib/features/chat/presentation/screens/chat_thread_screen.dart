import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/services/media_service.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/chat/application/chat_logic.dart';
import 'package:prostuti/features/chat/application/chat_room.dart';
import 'package:prostuti/features/chat/application/chat_thread_controller.dart';
import 'package:prostuti/features/chat/data/chat_models.dart';
import 'package:prostuti/features/chat/presentation/widgets/chat_composer.dart';
import 'package:prostuti/features/chat/presentation/widgets/chat_errors.dart';
import 'package:prostuti/features/chat/presentation/widgets/message_bubble.dart';
import 'package:prostuti/features/chat/presentation/widgets/thread_header.dart';
import 'package:prostuti/features/profile/data/profile.dart';

enum _MessageAction { reply, copy, delete, retry, discard }

/// One conversation: live messages, typing/presence, replies, images,
/// read receipts. Works offline (cached page + queued text messages).
class ChatThreadScreen extends ConsumerStatefulWidget {
  const ChatThreadScreen({required this.conversationId, super.key});
  final String conversationId;

  @override
  ConsumerState<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends ConsumerState<ChatThreadScreen> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _replyTo = ValueNotifier<ChatMessage?>(null);
  final _showJump = ValueNotifier<bool>(false);
  late final AppLifecycleListener _lifecycle;
  bool _routeVisible = true;

  String get _id => widget.conversationId;
  ChatMessagesNotifier get _messages => ref.read(chatMessagesProvider(_id).notifier);

  @override
  void initState() {
    super.initState();
    registerChatFailureMessages();
    _lifecycle = AppLifecycleListener(onStateChange: (_) => _syncVisibility());
    _scroll.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A route covered by another one has its tickers disabled: treat it as
    // not visible, so messages arriving meanwhile stay unread.
    _routeVisible = TickerMode.valuesOf(context).enabled;
    _syncVisibility();
  }

  void _syncVisibility() {
    final state = WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    _messages.setForeground(visible: _routeVisible && state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _text.dispose();
    _focus.dispose();
    _replyTo.dispose();
    _showJump.dispose();
    super.dispose();
  }

  void _onScroll() => _showJump.value = _scroll.hasClients && _scroll.offset > 480;

  void _jumpToLatest() {
    if (!_scroll.hasClients || _scroll.offset == 0) return;
    _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  String _authorName(ChatMessage m) {
    final l = context.l10n;
    if (m.senderId == ref.read(currentUserIdProvider)) return l.chatYou;
    final member = ref.read(chatConversationProvider(_id)).value?.member(m.senderId);
    return member?.user.displayName ?? l.chatUnknownUser;
  }

  Future<void> _send() async {
    final text = _text.text;
    if (text.trim().isEmpty) return;
    final reply = _replyTo.value;
    _text.clear();
    _replyTo.value = null;
    _jumpToLatest();
    try {
      await _messages.sendText(text, replyToId: reply?.id);
    } on Object catch (e) {
      if (!mounted) return;
      // Rejected before anything was shown (client-side rate limit): give
      // the text back instead of losing it.
      if (AppFailure.from(e) is RateLimitFailure && _text.text.isEmpty) {
        _text.text = text;
        _replyTo.value = reply;
      }
      showChatError(context, e);
    }
  }

  Future<void> _pickImage() async {
    final l = context.l10n;
    if (!ConnectivityService.instance.isOnline) {
      showInfoSnack(context, l.offlineUnavailable);
      return;
    }
    try {
      final bytes = await ref.read(mediaServiceProvider).pickOne();
      if (bytes == null || !mounted) return;
      final reply = _replyTo.value;
      _replyTo.value = null;
      _jumpToLatest();
      await _messages.sendImage(bytes, replyToId: reply?.id);
    } on NetworkFailure {
      if (mounted) showInfoSnack(context, l.offlineUnavailable);
    } on Object catch (e) {
      if (mounted) showChatError(context, e);
    }
  }

  void _reply(ChatMessage m) {
    _replyTo.value = m;
    _focus.requestFocus();
  }

  Future<void> _retry(ChatMessage m) async {
    try {
      await _messages.retrySend(m.id);
    } on NetworkFailure {
      if (mounted) showInfoSnack(context, context.l10n.offlineUnavailable);
    } on Object catch (e) {
      if (mounted) showChatError(context, e);
    }
  }

  Future<void> _showActions(ChatMessage m, {required bool isMine}) async {
    if (m.isSystem) return;
    final l = context.l10n;
    final failed = m.status == MessageStatus.failed;
    final actions = <_MessageAction>[
      if (!m.isPending && !m.isDeleted) _MessageAction.reply,
      if (m.kind == MessageKind.text && !m.isDeleted && (m.body?.isNotEmpty ?? false)) _MessageAction.copy,
      if (failed) ...[_MessageAction.retry, _MessageAction.discard],
      if (isMine && !m.isPending && !m.isDeleted) _MessageAction.delete,
    ];
    if (actions.isEmpty) return;
    final scheme = Theme.of(context).colorScheme;
    final picked = await showModalBottomSheet<_MessageAction>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a in actions)
              ListTile(
                leading: Icon(switch (a) {
                  _MessageAction.reply => Icons.reply_rounded,
                  _MessageAction.copy => Icons.copy_rounded,
                  _MessageAction.retry => Icons.refresh_rounded,
                  _MessageAction.discard => Icons.close_rounded,
                  _MessageAction.delete => Icons.delete_outline_rounded,
                }, color: a == _MessageAction.delete ? scheme.error : null),
                title: Text(switch (a) {
                  _MessageAction.reply => l.chatActionReply,
                  _MessageAction.copy => l.chatActionCopy,
                  _MessageAction.retry => l.chatActionRetry,
                  _MessageAction.discard => l.chatActionDiscard,
                  _MessageAction.delete => l.chatActionDelete,
                }, style: a == _MessageAction.delete ? TextStyle(color: scheme.error) : null),
                onTap: () => Navigator.pop(ctx, a),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    switch (picked) {
      case _MessageAction.reply:
        _reply(m);
      case _MessageAction.copy:
        await Clipboard.setData(ClipboardData(text: m.body ?? ''));
        if (mounted) showInfoSnack(context, l.chatCopied);
      case _MessageAction.retry:
        await _retry(m);
      case _MessageAction.discard:
        _messages.discard(m.id);
      case _MessageAction.delete:
        final ok = await confirmDialog(
          context,
          title: l.chatDeleteConfirmTitle,
          message: l.chatDeleteConfirmBody,
          confirmLabel: l.delete,
          destructive: true,
        );
        if (!ok || !mounted) return;
        try {
          await _messages.deleteMessage(m.id);
        } on Object catch (e) {
          if (mounted) showChatError(context, e);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final missing = ref.watch(
      chatConversationProvider(_id).select((a) => a.value == null && a.error is NotFoundFailure),
    );
    final online = ref.watch(isOnlineProvider).value ?? true;

    return Scaffold(
      appBar: ThreadAppBar(conversationId: _id),
      body: missing
          ? EmptyView(icon: Icons.speaker_notes_off_outlined, title: l.chatErrorConversationMissing)
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: _MessageList(
                          conversationId: _id,
                          controller: _scroll,
                          offline: !online,
                          onLongPress: (m, {required isMine}) => unawaited(_showActions(m, isMine: isMine)),
                          onReply: _reply,
                          onRetry: (m) => unawaited(_retry(m)),
                        ),
                      ),
                      Positioned(
                        right: Gap.lg,
                        bottom: Gap.md,
                        child: ValueListenableBuilder<bool>(
                          valueListenable: _showJump,
                          builder: (context, show, _) => AnimatedScale(
                            scale: show ? 1 : 0,
                            duration: const Duration(milliseconds: 160),
                            child: FloatingActionButton.small(
                              heroTag: null,
                              tooltip: l.chatScrollToLatest,
                              onPressed: show ? _jumpToLatest : null,
                              child: const Icon(Icons.keyboard_arrow_down_rounded),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ValueListenableBuilder<ChatMessage?>(
                  valueListenable: _replyTo,
                  builder: (context, reply, _) => reply == null
                      ? const SizedBox.shrink()
                      : ReplyPreviewBar(
                          message: reply,
                          authorName: _authorName(reply),
                          onCancel: () => _replyTo.value = null,
                        ),
                ),
                ChatComposer(
                  controller: _text,
                  focusNode: _focus,
                  imageEnabled: online,
                  onSend: () => unawaited(_send()),
                  onPickImage: () => unawaited(_pickImage()),
                  onChanged: (_) => ref.read(chatRoomProvider(_id).notifier).notifyTyping(),
                ),
              ],
            ),
    );
  }
}

typedef _LongPress = void Function(ChatMessage m, {required bool isMine});

/// The reversed message list. Watches only what it renders, so typing in
/// the composer never rebuilds it.
class _MessageList extends ConsumerWidget {
  const _MessageList({
    required this.conversationId,
    required this.controller,
    required this.offline,
    required this.onLongPress,
    required this.onReply,
    required this.onRetry,
  });

  final String conversationId;
  final ScrollController controller;
  final bool offline;
  final _LongPress onLongPress;
  final ValueChanged<ChatMessage> onReply;
  final ValueChanged<ChatMessage> onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final view = ref.watch(chatThreadViewProvider(conversationId));
    final typing = ref.watch(chatRoomProvider(conversationId).select((s) => s.typing));
    final detail = ref.watch(chatConversationProvider(conversationId)).value;
    final myId = ref.watch(currentUserIdProvider);
    final notifier = ref.read(chatMessagesProvider(conversationId).notifier);
    final s = view.state;

    if (s.isLoadingFirst && s.items.isEmpty) return const _ThreadSkeleton();
    if (s.error != null && s.items.isEmpty) {
      return ErrorView(error: s.error!, onRetry: () => unawaited(notifier.refresh()));
    }
    if (s.isEmpty && typing.isEmpty) {
      return EmptyView(
        icon: Icons.waving_hand_outlined,
        title: l.chatThreadEmptyTitle,
        message: l.chatThreadEmptyMessage,
      );
    }

    final isGroup = detail?.isGroup ?? false;
    final members = <String, UserSummary>{for (final m in detail?.members ?? const <ChatMember>[]) m.userId: m.user};
    String authorName(ChatMessage m) =>
        m.senderId == myId ? l.chatYou : members[m.senderId]?.displayName ?? l.chatUnknownUser;
    String? typingLabel() {
      if (typing.isEmpty) return null;
      if (!isGroup || typing.length > 1) return isGroup ? l.chatTypingMany : l.chatTyping;
      final name = members[typing.first]?.displayName;
      return name == null ? l.chatTypingMany : l.chatTypingNamed(name);
    }

    final head = typing.isEmpty ? 0 : 1;
    final count = view.entries.length + head + 1;

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        // Reversed list: "after" = towards older messages at the top.
        if (n.metrics.extentAfter < 800 && s.hasMore && !s.isLoadingMore && s.error == null) {
          unawaited(notifier.loadMore());
        }
        return false;
      },
      child: ListView.builder(
        controller: controller,
        reverse: true,
        padding: const EdgeInsets.only(top: Gap.sm, bottom: Gap.sm),
        itemCount: count,
        findChildIndexCallback: (key) {
          if (key is! ValueKey<String>) return null;
          final index = view.indexById[key.value];
          return index == null ? null : index + head;
        },
        itemBuilder: (context, i) {
          if (head == 1 && i == 0) return TypingBubble(key: const ValueKey('typing'), label: typingLabel());
          final j = i - head;
          if (j == view.entries.length) {
            return _ListTop(state: s, onRetry: () => unawaited(notifier.retry()));
          }
          final entry = view.entries[j];
          switch (entry) {
            case DayEntry():
              return DaySeparator(key: ValueKey('day:${entry.day.toIso8601String()}'), entry: entry);
            case MessageEntry(:final message):
              final isMine = message.senderId == myId;
              final replyId = message.replyToId;
              final target = replyId == null ? null : view.byId[replyId];
              return MessageBubble(
                key: ValueKey(message.id),
                entry: entry,
                isMine: isMine,
                isGroup: isGroup,
                sender: members[message.senderId],
                replyTarget: target,
                replyAuthorName: target == null ? null : authorName(target),
                seen: view.seen?.messageId == message.id ? view.seen : null,
                offline: offline,
                onLongPress: () => onLongPress(message, isMine: isMine),
                onReply: () => onReply(message),
                onRetry: () => onRetry(message),
              );
          }
        },
      ),
    );
  }
}

/// Top of the (reversed) list: older-page spinner, retry, or "start".
class _ListTop extends StatelessWidget {
  const _ListTop({required this.state, required this.onRetry});

  final MessagesState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(Gap.lg),
        child: Center(child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4))),
      );
    }
    if (state.error != null) {
      return Center(
        child: TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: Text(l.retry)),
      );
    }
    if (!state.hasMore) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xl, Gap.xl, Gap.sm),
        child: Column(
          children: [
            Icon(Icons.forum_outlined, color: Theme.of(context).colorScheme.primary),
            Gap.h8,
            Text(
              l.chatConversationStart,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    return const SizedBox(height: Gap.xl);
  }
}

class _ThreadSkeleton extends StatelessWidget {
  const _ThreadSkeleton();

  @override
  Widget build(BuildContext context) {
    const widths = [180.0, 120.0, 220.0, 90.0, 160.0, 200.0, 110.0];
    return SkeletonShimmer(
      child: ListView.builder(
        reverse: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Gap.lg),
        itemCount: widths.length,
        itemBuilder: (_, i) => Align(
          alignment: i.isEven ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: Gap.sm),
            child: SkeletonBox(width: widths[i], height: 38, radius: 18),
          ),
        ),
      ),
    );
  }
}
