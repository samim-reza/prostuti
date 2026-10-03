import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/app_image.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/chat/application/chat_room.dart';
import 'package:prostuti/features/chat/application/chat_thread_controller.dart';
import 'package:prostuti/features/chat/data/chat_models.dart';
import 'package:prostuti/features/chat/presentation/widgets/chat_errors.dart';
import 'package:prostuti/features/chat/presentation/widgets/chat_format.dart';
import 'package:prostuti/features/chat/presentation/widgets/conversation_tile.dart';

/// "Typing…" / "online" / member count line under the conversation title.
String? threadSubtitle(
  AppLocalizations l,
  ConversationDetail d,
  ChatRoomState room,
  String? myId,
  String Function(Object) n,
) {
  if (room.typing.isNotEmpty) {
    if (!d.isGroup) return l.chatTyping;
    if (room.typing.length > 1) return l.chatTypingMany;
    final typist = d.member(room.typing.first)?.user.displayName;
    return typist == null ? l.chatTypingMany : l.chatTypingNamed(typist);
  }
  if (!d.isGroup) return room.online.isNotEmpty ? l.chatOnline : null;
  final count = d.members.length;
  final online = room.online.length;
  return online > 0 ? l.chatMembersOnline(n(count), n(online)) : l.chatMembersCount(n(count));
}

enum _MenuAction { mute, profile, members }

/// App bar of a conversation: avatar (+ online dot), name, live subtitle and
/// an overflow menu (mute, profile / members).
class ThreadAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const ThreadAppBar({required this.conversationId, super.key});

  final String conversationId;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final detail = ref.watch(chatConversationProvider(conversationId));
    final room = ref.watch(chatRoomProvider(conversationId));
    final myId = ref.watch(currentUserIdProvider);
    final d = detail.value;

    Widget title;
    if (d == null) {
      title = detail.hasError
          ? Text(l.chatTitle)
          : const SkeletonShimmer(
              child: Row(
                children: [
                  SkeletonBox(width: 38, height: 38, radius: 19),
                  Gap.w12,
                  SkeletonBox(width: 120, height: 16),
                ],
              ),
            );
    } else {
      final name = detailTitle(l, d, myId);
      final other = d.otherUser(myId);
      final subtitle = threadSubtitle(l, d, room, myId, context.n);
      final typing = room.typing.isNotEmpty;
      title = InkWell(
        borderRadius: Radii.button,
        onTap: () => d.isGroup ? showMembersSheet(context, d, myId) : _openProfile(context, other?.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.xs),
          child: Row(
            children: [
              ConversationAvatar(
                isGroup: d.isGroup,
                name: name,
                url: d.isGroup ? d.avatarUrl : other?.avatarUrl,
                radius: 19,
                online: !d.isGroup && room.online.isNotEmpty,
              ),
              Gap.w12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: subtitle == null
                          ? const SizedBox.shrink()
                          : Text(
                              subtitle,
                              key: ValueKey(subtitle),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: typing ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                                fontStyle: typing ? FontStyle.italic : FontStyle.normal,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final muted = d?.member(myId ?? '')?.muted ?? false;
    return AppBar(
      titleSpacing: 0,
      title: title,
      actions: [
        if (d != null)
          PopupMenuButton<_MenuAction>(
            tooltip: l.chatMoreTooltip,
            onSelected: (a) async {
              switch (a) {
                case _MenuAction.mute:
                  try {
                    await ref.read(chatConversationProvider(conversationId).notifier).setMuted(muted: !muted);
                    if (context.mounted) showInfoSnack(context, muted ? l.chatUnmutedSnack : l.chatMutedSnack);
                  } on Object catch (e) {
                    if (context.mounted) showChatError(context, e);
                  }
                case _MenuAction.profile:
                  _openProfile(context, d.otherUser(myId)?.id);
                case _MenuAction.members:
                  unawaited(showMembersSheet(context, d, myId));
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _MenuAction.mute,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(muted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined),
                  title: Text(muted ? l.chatUnmute : l.chatMute),
                ),
              ),
              if (d.isGroup)
                PopupMenuItem(
                  value: _MenuAction.members,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.groups_outlined),
                    title: Text(l.chatViewMembers),
                  ),
                )
              else
                PopupMenuItem(
                  value: _MenuAction.profile,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline_rounded),
                    title: Text(l.chatViewProfile),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  static void _openProfile(BuildContext context, String? userId) {
    if (userId == null) return;
    context.push(Routes.userProfile(userId)).ignore();
  }
}

/// Bottom sheet listing a group's members (tap → profile).
Future<void> showMembersSheet(BuildContext context, ConversationDetail d, String? myId) {
  final l = context.l10n;
  final members = [...d.members]
    ..sort((a, b) {
      int rank(ChatMember m) => switch (m.role) {
        'owner' => 0,
        'admin' => 1,
        _ => 2,
      };
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.user.displayName.compareTo(b.user.displayName);
    });
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => ListView.builder(
        controller: scroll,
        itemCount: members.length + 1,
        itemBuilder: (ctx, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.sm),
              child: Text(
                '${l.chatMembersTitle} · ${ctx.n(members.length)}',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            );
          }
          final m = members[i - 1];
          final isMe = m.userId == myId;
          final role = switch (m.role) {
            'owner' => l.chatRoleOwner,
            'admin' => l.chatRoleAdmin,
            _ => null,
          };
          return ListTile(
            minTileHeight: 56,
            leading: UserAvatar(name: m.user.displayName, url: m.user.avatarUrl),
            title: Text(isMe ? '${m.user.displayName} (${l.chatYou})' : m.user.displayName),
            subtitle: m.user.username.isEmpty ? null : Text('@${m.user.username}'),
            trailing: role == null
                ? null
                : Chip(label: Text(role), visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
            onTap: isMe
                ? null
                : () {
                    Navigator.pop(ctx);
                    context.push(Routes.userProfile(m.userId)).ignore();
                  },
          );
        },
      ),
    ),
  );
}
