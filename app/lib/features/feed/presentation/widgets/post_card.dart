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
import 'package:prostuti/features/feed/application/reaction_controller.dart';
import 'package:prostuti/features/feed/data/post.dart';
import 'package:prostuti/features/feed/l10n/social_failures.dart';
import 'package:prostuti/features/feed/presentation/widgets/expandable_text.dart';
import 'package:prostuti/features/feed/presentation/widgets/post_attachments.dart';
import 'package:prostuti/features/feed/presentation/widgets/post_image_grid.dart';
import 'package:prostuti/features/feed/presentation/widgets/post_labels.dart';
import 'package:prostuti/features/feed/presentation/widgets/post_menu.dart';
import 'package:prostuti/features/feed/presentation/widgets/reaction_picker.dart';
import 'package:share_plus/share_plus.dart';

/// A post in the feed, on a profile or on the detail screen.
class PostCard extends ConsumerWidget {
  const PostCard({required this.post, this.inDetail = false, this.onCommentTap, super.key});

  final Post post;

  /// On the detail screen the body starts expanded and taps don't navigate.
  final bool inDetail;

  /// Defaults to opening the post's detail screen.
  final VoidCallback? onCommentTap;

  void _openDetail(BuildContext context) {
    if (inDetail || post.pendingSync) return;
    unawaited(context.push(Routes.postDetail(post.id)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMine = ref.watch(currentUserIdProvider.select((id) => id == post.author.id));
    final hasStats = post.reactionCount > 0 || post.commentCount > 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PostHeader(post: post, onMenu: post.pendingSync ? null : () => unawaited(showPostMenu(context, ref, post))),
          InkWell(
            onTap: inDetail || post.pendingSync ? null : () => _openDetail(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (post.hasBody)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.sm),
                    child: ExpandableText(post.body!.trim(), initiallyExpanded: inDetail),
                  ),
                if (post.kind != PostKind.text)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.sm),
                    child: PostAttachment(post: post, isMine: isMine),
                  ),
              ],
            ),
          ),
          if (post.imageUrls.isNotEmpty) PostImageGrid(urls: post.imageUrls),
          if (hasStats) _StatsRow(post: post, onCommentsTap: onCommentTap ?? () => _openDetail(context)),
          Divider(height: 1, indent: Gap.md, endIndent: Gap.md, color: Theme.of(context).colorScheme.outlineVariant),
          _ActionBar(post: post, onComment: onCommentTap ?? () => _openDetail(context)),
        ],
      ),
    );
  }
}

class _PostHeader extends StatelessWidget {
  const _PostHeader({required this.post, required this.onMenu});

  final Post post;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final meta = theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.2);
    void openProfile() => unawaited(context.push(Routes.userProfile(post.author.id)));
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.xs, Gap.sm),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: post.author.displayName,
            excludeSemantics: true,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: openProfile,
              child: UserAvatar(name: post.author.displayName, url: post.author.avatarUrl, radius: 21),
            ),
          ),
          Gap.w12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: openProfile,
                  child: Text(
                    post.author.displayName,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Gap.h4,
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        [
                          Fmt.timeAgo(post.createdAt, bangla: context.isBn),
                          if (post.isEdited) l.feedEdited,
                        ].join(' · '),
                        style: meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(' · ', style: meta),
                    Icon(post.visibility.icon, size: 13, color: muted, semanticLabel: post.visibility.label(l)),
                    if (post.pendingSync) ...[
                      Gap.w8,
                      Tooltip(
                        message: l.offlineSaved,
                        child: Icon(Icons.schedule_rounded, size: 14, color: muted, semanticLabel: l.offlineSaved),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (onMenu != null)
            IconButton(icon: const Icon(Icons.more_horiz_rounded), tooltip: l.feedPostOptions, onPressed: onMenu),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.post, required this.onCommentsTap});

  final Post post;
  final VoidCallback onCommentsTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final top = post.topReactions();
    final bn = context.isBn;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xs, Gap.sm, Gap.xs),
      child: Row(
        children: [
          if (post.reactionCount > 0)
            Semantics(
              label: l.feedReactionsSemantics(Fmt.count(post.reactionCount, bangla: bn)),
              excludeSemantics: true,
              child: Row(
                children: [
                  _ReactionStack(types: top),
                  Gap.w4,
                  Text(Fmt.count(post.reactionCount, bangla: bn), style: style),
                ],
              ),
            ),
          const Spacer(),
          if (post.commentCount > 0)
            TextButton(
              onPressed: onCommentsTap,
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 36),
                padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                foregroundColor: theme.colorScheme.onSurfaceVariant,
                textStyle: theme.textTheme.bodySmall,
              ),
              child: Text(l.feedCommentsCount(Fmt.count(post.commentCount, bangla: bn))),
            )
          else
            const SizedBox(height: 36),
        ],
      ),
    );
  }
}

/// Up to three overlapping reaction emojis.
class _ReactionStack extends StatelessWidget {
  const _ReactionStack({required this.types});

  final List<ReactionType> types;

  static const _size = 20.0;
  static const _overlap = 6.0;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return SizedBox(
      width: _size + (types.length - 1).clamp(0, 2) * (_size - _overlap),
      height: _size,
      child: Stack(
        children: [
          for (var i = types.length - 1; i >= 0; i--)
            Positioned(
              left: i * (_size - _overlap),
              child: Container(
                width: _size,
                height: _size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: surface, width: 1.5),
                ),
                child: Text(types[i].emoji, style: const TextStyle(fontSize: 13, height: 1)),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionBar extends ConsumerWidget {
  const _ActionBar({required this.post, required this.onComment});

  final Post post;
  final VoidCallback onComment;

  void _share(BuildContext context) {
    final l = context.l10n;
    final bn = context.isBn;
    final exam = post.examResult;
    final text = [
      post.author.displayName,
      if (post.hasBody) post.body!.trim(),
      if (exam != null)
        l.feedShareExamResult(Fmt.score(exam.score, bangla: bn), Fmt.score(exam.maxScore, bangla: bn), exam.title),
      ...post.imageUrls,
      '— ${l.feedShareFooter}',
    ].join('\n\n');
    final box = context.findRenderObject() as RenderBox?;
    unawaited(
      SharePlus.instance.share(
        ShareParams(text: text, sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.xs, vertical: Gap.xxs),
      child: Row(
        children: [
          Expanded(child: _ReactButton(post: post)),
          Expanded(
            child: _BarButton(icon: Icons.mode_comment_outlined, label: l.feedComment, onTap: onComment),
          ),
          Expanded(
            child: Builder(
              builder: (btnContext) =>
                  _BarButton(icon: Icons.share_outlined, label: l.feedShare, onTap: () => _share(btnContext)),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.onLongPress,
    this.color,
    this.leading,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return TextButton(
      onPressed: onTap,
      onLongPress: onLongPress,
      style: TextButton.styleFrom(
        foregroundColor: fg,
        minimumSize: const Size.fromHeight(44),
        shape: const RoundedRectangleBorder(borderRadius: Radii.button),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          leading ?? Icon(icon, size: 20),
          Gap.w8,
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

/// Tap: like / remove my reaction. Long-press: pick one of six reactions.
class _ReactButton extends ConsumerWidget {
  const _ReactButton({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final mine = post.myReaction;
    final scheme = Theme.of(context).colorScheme;
    void onError(Object e) {
      if (context.mounted) showSocialError(context, e);
    }

    final controller = ref.watch(reactionControllerProvider);
    return Semantics(
      hint: l.feedReactionPickerHint,
      selected: mine != null,
      child: _BarButton(
        icon: Icons.thumb_up_outlined,
        leading: mine == null
            ? null
            : AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                child: Text(mine.emoji, key: ValueKey(mine), style: const TextStyle(fontSize: 18, height: 1.1)),
              ),
        label: (mine ?? ReactionType.like).label(l),
        color: mine?.color(scheme),
        onTap: () => controller.toggle(post, onError: onError),
        onLongPress: () async {
          final picked = await showReactionPicker(context, current: mine);
          if (picked != null) controller.set(post, picked, onError: onError);
        },
      ),
    );
  }
}
