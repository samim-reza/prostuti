import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/app_image.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/feed/application/comments_controller.dart';
import 'package:prostuti/features/feed/data/comment.dart';
import 'package:prostuti/features/feed/l10n/social_failures.dart';
import 'package:prostuti/features/feed/presentation/widgets/report_sheet.dart';

/// Which top-level comments of a post have their replies expanded.
class ExpandedReplies extends Notifier<Set<String>> {
  ExpandedReplies(this.postId);

  final String postId;

  @override
  Set<String> build() => const {};

  void expand(String commentId) {
    if (!state.contains(commentId)) state = {...state, commentId};
  }

  void collapse(String commentId) => state = {...state}..remove(commentId);
}

final expandedRepliesProvider = NotifierProvider.autoDispose.family<ExpandedReplies, Set<String>, String>(
  ExpandedReplies.new,
);

/// A top-level comment plus its (lazily loaded) replies.
class CommentThread extends ConsumerWidget {
  const CommentThread({required this.comment, required this.postAuthorId, required this.onReply, super.key});

  final Comment comment;
  final String postAuthorId;
  final void Function(Comment target) onReply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final expanded = ref.watch(expandedRepliesProvider(comment.postId).select((s) => s.contains(comment.id)));
    final expander = ref.read(expandedRepliesProvider(comment.postId).notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CommentTile(comment: comment, postAuthorId: postAuthorId, onReply: onReply),
        if (expanded)
          _Replies(
            postId: comment.postId,
            parentId: comment.id,
            postAuthorId: postAuthorId,
            onReply: onReply,
            onHide: () => expander.collapse(comment.id),
          )
        else if (comment.replyCount > 0)
          Padding(
            padding: const EdgeInsets.only(left: 52),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => expander.expand(comment.id),
                icon: const Icon(Icons.subdirectory_arrow_right_rounded, size: 18),
                label: Text(l.feedViewReplies(context.n(comment.replyCount))),
                style: TextButton.styleFrom(minimumSize: const Size(44, 36)),
              ),
            ),
          ),
      ],
    );
  }
}

class _Replies extends ConsumerWidget {
  const _Replies({
    required this.postId,
    required this.parentId,
    required this.postAuthorId,
    required this.onReply,
    required this.onHide,
  });

  final String postId;
  final String parentId;
  final String postAuthorId;
  final void Function(Comment target) onReply;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final key = (postId: postId, parentId: parentId);
    final state = ref.watch(repliesProvider(key));
    final notifier = ref.read(repliesProvider(key).notifier);
    final buttonStyle = TextButton.styleFrom(minimumSize: const Size(44, 36));
    return Padding(
      padding: const EdgeInsets.only(left: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final reply in state.items)
            CommentTile(key: ValueKey(reply.id), comment: reply, postAuthorId: postAuthorId, onReply: onReply),
          if (state.isLoadingFirst || state.isLoadingMore)
            const Padding(
              padding: EdgeInsets.all(Gap.sm),
              child: Center(child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (state.error != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => unawaited(notifier.retry()),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(l.retry),
                style: buttonStyle,
              ),
            ),
          Wrap(
            children: [
              if (state.hasMore && !state.isLoadingFirst && !state.isLoadingMore && state.error == null)
                TextButton(
                  onPressed: () => unawaited(notifier.loadMore()),
                  style: buttonStyle,
                  child: Text(l.feedMoreReplies),
                ),
              if (!state.isLoadingFirst)
                TextButton(onPressed: onHide, style: buttonStyle, child: Text(l.feedHideReplies)),
            ],
          ),
        ],
      ),
    );
  }
}

/// One comment bubble with like / reply / options.
class CommentTile extends ConsumerWidget {
  const CommentTile({required this.comment, required this.postAuthorId, required this.onReply, super.key});

  final Comment comment;
  final String postAuthorId;
  final void Function(Comment target) onReply;

  Future<void> _options(BuildContext context, WidgetRef ref, {required bool canDelete, required bool isMine}) async {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final actions = ref.read(commentActionsProvider(comment.postId));
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: Text(l.feedReply),
              onTap: () => Navigator.pop(ctx, 'reply'),
            ),
            if (canDelete)
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: scheme.error),
                title: Text(l.feedDeleteComment, style: TextStyle(color: scheme.error)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            if (!isMine)
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(l.feedReportComment),
                onTap: () => Navigator.pop(ctx, 'report'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case 'reply':
        onReply(comment);
      case 'delete':
        if (!ensureOnline(context)) return;
        final ok = await confirmDialog(
          context,
          title: l.feedDeleteCommentConfirm,
          confirmLabel: l.delete,
          destructive: true,
        );
        if (!ok || !context.mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        try {
          await actions.delete(comment);
          messenger.showSnackBar(SnackBar(content: Text(l.feedCommentDeleted)));
        } on Object catch (e) {
          if (context.mounted) showSocialError(context, e);
        }
      case 'report':
        await reportFlow(context, (reason) => actions.report(comment, reason));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final me = ref.watch(currentUserIdProvider);
    final isMine = comment.author.id == me;
    final canDelete = !comment.pendingSync && (isMine || postAuthorId == me);
    final muted = theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant);
    final small = comment.isReply;
    void openProfile() => unawaited(context.push(Routes.userProfile(comment.author.id)));
    void like() {
      unawaited(
        ref.read(commentActionsProvider(comment.postId)).toggleLike(comment).catchError((Object e) {
          if (context.mounted) showSocialError(context, e);
        }),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            label: comment.author.displayName,
            excludeSemantics: true,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: openProfile,
              child: UserAvatar(
                name: comment.author.displayName,
                url: comment.author.avatarUrl,
                radius: small ? 14 : 18,
              ),
            ),
          ),
          Gap.w8,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onLongPress: comment.pendingSync
                      ? null
                      : () => unawaited(_options(context, ref, canDelete: canDelete, isMine: isMine)),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.sm),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                      borderRadius: Radii.card,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: openProfile,
                          child: Text(comment.author.displayName, style: theme.textTheme.labelLarge),
                        ),
                        Gap.h4,
                        Text(comment.body, style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    Gap.w8,
                    Text(Fmt.timeAgo(comment.createdAt, bangla: context.isBn), style: muted),
                    if (comment.pendingSync) ...[
                      Gap.w4,
                      Tooltip(
                        message: l.offlineSaved,
                        child: Icon(
                          Icons.schedule_rounded,
                          size: 13,
                          color: scheme.onSurfaceVariant,
                          semanticLabel: l.offlineSaved,
                        ),
                      ),
                    ],
                    _SmallAction(label: l.feedLikeComment, selected: comment.likedByMe, onTap: like),
                    _SmallAction(label: l.feedReply, onTap: () => onReply(comment)),
                    const Spacer(),
                    if (comment.likeCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: Gap.xs),
                        child: Text('👍 ${Fmt.count(comment.likeCount, bangla: context.isBn)}', style: muted),
                      ),
                    if (!comment.pendingSync)
                      IconButton(
                        tooltip: l.feedCommentOptions,
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        icon: Icon(Icons.more_horiz_rounded, color: scheme.onSurfaceVariant),
                        onPressed: () => unawaited(_options(context, ref, canDelete: canDelete, isMine: isMine)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({required this.label, required this.onTap, this.selected = false});

  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    return Semantics(
      selected: selected,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 36),
          padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
          foregroundColor: color,
          textStyle: theme.textTheme.labelMedium?.copyWith(fontWeight: selected ? FontWeight.w700 : FontWeight.w600),
        ),
        child: Text(label),
      ),
    );
  }
}

/// Bottom-pinned comment box with an optional "Replying to …" chip.
class CommentComposer extends StatelessWidget {
  const CommentComposer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
    this.replyTo,
    this.onCancelReply,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;
  final Comment? replyTo;
  final VoidCallback? onCancelReply;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final target = replyTo;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.sm, Gap.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (target != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.xs),
                  child: InputChip(
                    avatar: const Icon(Icons.reply_rounded, size: 18),
                    label: Text(l.feedReplyingTo(target.author.displayName), overflow: TextOverflow.ellipsis),
                    onDeleted: onCancelReply,
                    deleteButtonTooltipMessage: l.feedCancelReply,
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      textCapitalization: TextCapitalization.sentences,
                      keyboardType: TextInputType.multiline,
                      decoration: InputDecoration(
                        hintText: target == null ? l.feedWriteComment : l.feedWriteReply,
                        counterText: '',
                        isDense: true,
                        filled: true,
                        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                        contentPadding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
                        border: const OutlineInputBorder(borderRadius: Radii.chip, borderSide: BorderSide.none),
                        enabledBorder: const OutlineInputBorder(borderRadius: Radii.chip, borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: Radii.chip,
                          borderSide: BorderSide(color: scheme.primary),
                        ),
                      ),
                    ),
                  ),
                  Gap.w4,
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) => IconButton.filled(
                      tooltip: l.feedSendComment,
                      onPressed: sending || value.text.trim().isEmpty ? null : onSend,
                      icon: sending
                          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_rounded),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
