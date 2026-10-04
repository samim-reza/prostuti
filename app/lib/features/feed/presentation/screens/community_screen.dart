import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/paged_list_view.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/chat/application/unread_chats_count_provider.dart';
import 'package:prostuti/features/feed/application/feed_controller.dart';
import 'package:prostuti/features/feed/presentation/widgets/feed_widgets.dart';
import 'package:prostuti/features/feed/presentation/widgets/post_card.dart';
import 'package:prostuti/features/friends/application/friends_controller.dart';

/// Community tab: infinite feed with a composer prompt, people search,
/// friends (pending-request badge) and messages (unread badge).
class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refreshBadges);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _refreshBadges() {
    ref.invalidate(incomingRequestCountProvider);
    // Realtime keeps it live; this catches anything missed in the background.
    unawaited(ref.read(unreadChatsCountProvider.notifier).refresh());
  }

  /// Opens a sub-screen and refreshes the badges when the user comes back.
  Future<void> _go(String location) async {
    await context.push(location);
    if (mounted) _refreshBadges();
  }

  Future<void> _refresh() async {
    _refreshBadges();
    await ref.read(feedProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final feed = ref.watch(feedProvider);
    final notifier = ref.read(feedProvider.notifier);
    final requests = ref.watch(incomingRequestCountProvider.select((v) => v.value ?? 0));
    final unread = ref.watch(unreadChatsCountProvider);
    const header = ComposerPromptCard();
    return Scaffold(
      appBar: AppBar(
        title: Text(l.feedTitle),
        actions: [
          IconButton(
            tooltip: l.feedSearchUsers,
            icon: const Icon(Icons.person_search_outlined),
            onPressed: () => unawaited(_go(Routes.userSearch)),
          ),
          IconButton(
            tooltip: requests > 0 ? l.feedFriendsActionBadge(context.n(requests)) : l.feedFriendsAction,
            icon: CountBadgeIcon(icon: Icons.people_alt_outlined, count: requests),
            onPressed: () => unawaited(_go(Routes.friends)),
          ),
          IconButton(
            tooltip: unread > 0 ? l.feedChatsActionBadge(context.n(unread)) : l.feedChatsAction,
            icon: CountBadgeIcon(icon: Icons.chat_bubble_outline_rounded, count: unread),
            onPressed: () => unawaited(_go(Routes.chats)),
          ),
          Gap.w4,
        ],
      ),
      body: PagedListView(
        state: feed,
        onLoadMore: () => unawaited(notifier.loadMore()),
        onRefresh: _refresh,
        onRetry: () => unawaited(notifier.retry()),
        padding: const EdgeInsets.only(bottom: Gap.xl),
        header: header,
        loading: const PostSkeletonList(header: header),
        empty: EmptyView(
          icon: Icons.forum_outlined,
          title: l.feedEmptyTitle,
          message: l.feedEmptyBody,
          action: () => unawaited(context.push(Routes.composePost)),
          actionLabel: l.feedWriteFirstPost,
        ),
        itemBuilder: (context, post, _) => Padding(
          key: ValueKey(post.id),
          padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.xs + 2),
          child: PostCard(post: post),
        ),
      ),
    );
  }
}
