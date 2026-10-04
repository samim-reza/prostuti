import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/feed/application/feed_controller.dart';
import 'package:prostuti/features/feed/data/post.dart';
import 'package:prostuti/features/feed/data/report.dart';
import 'package:prostuti/features/feed/l10n/social_failures.dart';
import 'package:prostuti/features/feed/presentation/screens/compose_post_screen.dart';
import 'package:prostuti/features/feed/presentation/widgets/report_sheet.dart';

enum _PostAction { save, edit, delete, report, block }

/// "Block {name}?" confirmation shared by posts, comments and profiles.
Future<bool> confirmBlock(BuildContext context, String name) {
  final l = context.l10n;
  return confirmDialog(
    context,
    title: l.feedBlockConfirmTitle(name),
    message: l.feedBlockConfirmBody,
    confirmLabel: l.feedBlock,
    destructive: true,
  );
}

/// Overflow actions of a post: save for every post, plus edit/delete for my
/// posts and report/block for everyone else's.
Future<void> showPostMenu(BuildContext context, WidgetRef ref, Post post) async {
  final l = context.l10n;
  final scheme = Theme.of(context).colorScheme;
  // Read everything from `ref` up front: the card may be gone after an await.
  final isMine = post.author.id == ref.read(currentUserIdProvider);
  final actions = ref.read(postActionsProvider);
  final action = await showModalBottomSheet<_PostAction>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.bookmark_add_outlined),
            title: Text(l.feedSavePost),
            onTap: () => Navigator.pop(ctx, _PostAction.save),
          ),
          if (isMine) ...[
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(l.feedEditPost),
              onTap: () => Navigator.pop(ctx, _PostAction.edit),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: scheme.error),
              title: Text(l.feedDeletePost, style: TextStyle(color: scheme.error)),
              onTap: () => Navigator.pop(ctx, _PostAction.delete),
            ),
          ] else ...[
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(l.feedReportPost),
              onTap: () => Navigator.pop(ctx, _PostAction.report),
            ),
            ListTile(
              leading: Icon(Icons.block_rounded, color: scheme.error),
              title: Text(l.feedBlockUser(post.author.displayName), style: TextStyle(color: scheme.error)),
              onTap: () => Navigator.pop(ctx, _PostAction.block),
            ),
          ],
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _PostAction.save:
      // Works offline: the save is queued and synced later.
      final messenger = ScaffoldMessenger.of(context);
      try {
        final synced = await actions.save(post);
        messenger.showSnackBar(SnackBar(content: Text(synced ? l.feedPostSaved : l.offlineSaved)));
      } on Object catch (e) {
        if (context.mounted) showSocialError(context, e);
      }
    case _PostAction.edit:
      if (!ensureOnline(context)) return;
      await ComposePostScreen.openEditor(context, post);
    case _PostAction.delete:
      if (!ensureOnline(context)) return;
      final ok = await confirmDialog(
        context,
        title: l.feedDeletePostConfirmTitle,
        message: l.feedDeletePostConfirmBody,
        confirmLabel: l.delete,
        destructive: true,
      );
      if (!ok || !context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      try {
        await actions.delete(post);
        messenger.showSnackBar(SnackBar(content: Text(l.feedPostDeleted)));
      } on Object catch (e) {
        if (context.mounted) showSocialError(context, e);
      }
    case _PostAction.report:
      await reportFlow(context, (reason) => actions.report(ReportTarget.post, post.id, reason));
    case _PostAction.block:
      if (!ensureOnline(context)) return;
      if (!await confirmBlock(context, post.author.displayName) || !context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      try {
        await actions.blockAuthor(post.author.id);
        messenger.showSnackBar(SnackBar(content: Text(l.feedUserBlocked)));
      } on Object catch (e) {
        if (context.mounted) showSocialError(context, e);
      }
  }
}
