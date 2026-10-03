import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/features/chat/application/unread_chats_count_provider.dart';

/// App-bar icon button opening the chat inbox, with an unread badge
/// (Bangla digits in the Bangla UI). Drop it into any `AppBar.actions`.
class ChatButton extends ConsumerWidget {
  const ChatButton({this.iconColor, super.key});

  final Color? iconColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadChatsCountProvider);
    final l = context.l10n;
    final label = count > 99 ? '${context.n(99)}+' : context.n(count);
    return IconButton(
      tooltip: count > 0 ? l.chatButtonTooltipUnread(label) : l.chatButtonTooltip,
      color: iconColor,
      onPressed: () => context.push(Routes.chats),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(label),
        child: Icon(count > 0 ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded),
      ),
    );
  }
}
