import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/paged_list_view.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/feed/application/comments_controller.dart';
import 'package:prostuti/features/feed/application/feed_controller.dart';
import 'package:prostuti/features/feed/data/comment.dart';
import 'package:prostuti/features/feed/data/post.dart';
import 'package:prostuti/features/feed/l10n/social_failures.dart';
import 'package:prostuti/features/feed/presentation/widgets/comment_widgets.dart';
import 'package:prostuti/features/feed/presentation/widgets/feed_widgets.dart';
import 'package:prostuti/features/feed/presentation/widgets/post_card.dart';

/// A post with its comments (oldest first, one level of replies) and a
/// pinned comment composer. Works offline from the cache; new comments are
/// queued with a pending-sync marker.
class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({required this.postId, super.key});

  final String postId;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  Comment? _replyTo;
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _startReply(Comment target) {
    setState(() => _replyTo = target);
    _focus.requestFocus();
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    final l = context.l10n;
    final replyTo = _replyTo;
    final actions = ref.read(commentActionsProvider(widget.postId));
    final expander = ref.read(expandedRepliesProvider(widget.postId).notifier);
    setState(() => _sending = true);
    try {
      final comment = await actions.add(body, replyTo: replyTo);
      if (!mounted) return;
      _text.clear();
      setState(() => _replyTo = null);
      if (comment.parentId != null) {
        expander.expand(comment.parentId!);
      } else {
        _scrollToEnd();
      }
      if (comment.pendingSync) showInfoSnack(context, l.offlineSaved);
    } on Object catch (e) {
      if (mounted) showSocialError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _refresh() async {
    final post = ref.read(postDetailProvider(widget.postId).notifier);
    final comments = ref.read(commentsProvider(widget.postId).notifier);
    await Future.wait([post.refresh().catchError((Object _) {}), comments.refresh()]);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // Keeps the comment actions (and their in-flight guards) alive here.
    ref
      ..watch(commentActionsProvider(widget.postId))
      ..listen<AsyncValue<Post?>>(postDetailProvider(widget.postId), (prev, next) {
        // Deleted from this screen (or elsewhere) → leave.
        if (prev?.value != null && next.hasValue && next.value == null) Navigator.of(context).maybePop();
      });
    final postAsync = ref.watch(postDetailProvider(widget.postId));

    return Scaffold(
      appBar: AppBar(title: Text(l.feedPostTitle)),
      body: postAsync.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const PostSkeletonList(count: 1),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(postDetailProvider(widget.postId))),
        data: (post) {
          if (post == null) {
            return EmptyView(
              icon: Icons.visibility_off_outlined,
              title: l.feedPostNotFound,
              message: l.feedPostNotFoundBody,
            );
          }
          return Column(
            children: [
              Expanded(
                child: _CommentsList(
                  post: post,
                  scroll: _scroll,
                  onReply: _startReply,
                  onComment: _focus.requestFocus,
                  onRefresh: _refresh,
                ),
              ),
              CommentComposer(
                controller: _text,
                focusNode: _focus,
                sending: _sending,
                onSend: () => unawaited(_send()),
                replyTo: _replyTo,
                onCancelReply: () => setState(() => _replyTo = null),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CommentsList extends ConsumerWidget {
  const _CommentsList({
    required this.post,
    required this.scroll,
    required this.onReply,
    required this.onComment,
    required this.onRefresh,
  });

  final Post post;
  final ScrollController scroll;
  final void Function(Comment target) onReply;
  final VoidCallback onComment;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final state = ref.watch(commentsProvider(post.id));
    final notifier = ref.read(commentsProvider(post.id).notifier);
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, 0),
          child: PostCard(post: post, inDetail: true, onCommentTap: onComment),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.sm),
          child: Text(l.feedCommentsTitle, style: theme.textTheme.titleMedium),
        ),
      ],
    );
    return PagedListView(
      controller: scroll,
      state: state,
      header: header,
      onLoadMore: () => unawaited(notifier.loadMore()),
      onRefresh: onRefresh,
      onRetry: () => unawaited(notifier.retry()),
      padding: const EdgeInsets.only(bottom: Gap.lg),
      loading: ListView(physics: const NeverScrollableScrollPhysics(), children: [header, const _CommentsSkeleton()]),
      empty: EmptyView(
        compact: true,
        icon: Icons.chat_bubble_outline_rounded,
        title: l.feedNoComments,
        message: l.feedNoCommentsBody,
      ),
      itemBuilder: (context, comment, _) =>
          CommentThread(key: ValueKey(comment.id), comment: comment, postAuthorId: post.author.id, onReply: onReply),
    );
  }
}

class _CommentsSkeleton extends StatelessWidget {
  const _CommentsSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
        child: Column(
          children: [
            for (var i = 0; i < 3; i++)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: Gap.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 36, height: 36, radius: 18),
                    Gap.w8,
                    Expanded(child: SkeletonBox(height: 56, radius: 16)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
