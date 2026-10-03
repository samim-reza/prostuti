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
import 'package:prostuti/core/widgets/paged_list_view.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/feed/application/feed_controller.dart';
import 'package:prostuti/features/feed/data/feed_repository.dart';
import 'package:prostuti/features/feed/data/report.dart';
import 'package:prostuti/features/feed/l10n/social_failures.dart';
import 'package:prostuti/features/feed/presentation/widgets/post_card.dart';
import 'package:prostuti/features/feed/presentation/widgets/post_menu.dart';
import 'package:prostuti/features/feed/presentation/widgets/report_sheet.dart';
import 'package:prostuti/features/friends/application/relationship_controller.dart';
import 'package:prostuti/features/friends/presentation/widgets/relationship_button.dart';
import 'package:prostuti/features/profile/data/profile.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';

/// Someone's profile: header, stats, relationship actions and their posts.
/// Renders offline from the profile / relationship / first-page caches.
class UserProfileScreen extends ConsumerStatefulWidget {
  const UserProfileScreen({required this.userId, super.key});

  final String userId;

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  @override
  void initState() {
    super.initState();
    // A seeded relationship paints instantly; confirm it with the server.
    final seeded = ref.read(relationshipSeedsProvider)[widget.userId] != null;
    if (seeded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(ref.read(relationshipProvider(widget.userId).notifier).reload().catchError((Object _) {}));
      });
    }
  }

  Future<void> _refresh() async {
    final id = widget.userId;
    try {
      await ref.read(profileRepositoryProvider).fetchById(id, force: true);
    } on Object {
      // The cached profile stays on screen.
    }
    if (!mounted) return;
    ref.invalidate(profileByIdProvider(id));
    unawaited(ref.read(relationshipProvider(id).notifier).reload().catchError((Object _) {}));
    await ref.read(authorFeedProvider(id).notifier).refresh();
  }

  Future<void> _menu(String choice, Profile profile) async {
    final l = context.l10n;
    switch (choice) {
      case 'report':
        final repo = ref.read(feedRepositoryProvider);
        await reportFlow(context, (r) => repo.report(target: ReportTarget.user, targetId: profile.id, reason: r));
      case 'block':
        if (!ensureOnline(context)) return;
        if (!await confirmBlock(context, profile.displayName) || !mounted) return;
        try {
          await ref.read(relationshipProvider(profile.id).notifier).block();
          if (mounted) showInfoSnack(context, l.feedUserBlocked);
        } on Object catch (e) {
          if (mounted) showSocialError(context, e);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final profileAsync = ref.watch(profileByIdProvider(widget.userId));
    final isMe = ref.watch(currentUserIdProvider.select((id) => id == widget.userId));
    final blocked = !isMe && (ref.watch(relationshipProvider(widget.userId)).value?.isBlocked ?? false);
    final profile = profileAsync.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(profile?.displayName ?? ''),
        actions: [
          if (!isMe && profile != null)
            PopupMenuButton<String>(
              tooltip: l.friendsMoreOptions,
              onSelected: (v) => unawaited(_menu(v, profile)),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'report',
                  child: ListTile(
                    leading: const Icon(Icons.flag_outlined),
                    title: Text(l.friendsReportUser),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (!blocked)
                  PopupMenuItem(
                    value: 'block',
                    child: ListTile(
                      leading: const Icon(Icons.block_rounded),
                      title: Text(l.friendsBlockUser),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: profileAsync.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const _ProfileSkeleton(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(profileByIdProvider(widget.userId))),
        data: (profile) {
          if (profile == null) {
            return EmptyView(
              icon: Icons.person_off_outlined,
              title: l.friendsUserNotFound,
              message: l.friendsUserNotFoundBody,
            );
          }
          final posts = ref.watch(authorFeedProvider(profile.id));
          final notifier = ref.read(authorFeedProvider(profile.id).notifier);
          return PagedListView(
            state: posts,
            header: _ProfileHeader(profile: profile, isMe: isMe, blocked: blocked),
            onLoadMore: () => unawaited(notifier.loadMore()),
            onRefresh: _refresh,
            onRetry: () => unawaited(notifier.retry()),
            padding: const EdgeInsets.only(bottom: Gap.xl),
            loading: ListView(
              children: [
                _ProfileHeader(profile: profile, isMe: isMe, blocked: blocked),
                const SkeletonCards(count: 2),
              ],
            ),
            empty: blocked
                ? const SizedBox.shrink()
                : EmptyView(compact: true, icon: Icons.article_outlined, title: l.friendsNoPosts),
            itemBuilder: (context, post, _) => Padding(
              key: ValueKey(post.id),
              padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.xs + 2),
              child: PostCard(post: post),
            ),
          );
        },
      ),
    );
  }
}

class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader({required this.profile, required this.isMe, required this.blocked});

  final Profile profile;
  final bool isMe;
  final bool blocked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bn = context.isBn;
    final bio = profile.bio?.trim();
    final district = profile.district?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 156,
          child: Stack(
            children: [
              Positioned.fill(
                bottom: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [scheme.primary, scheme.tertiary],
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: Gap.lg),
                      child: Icon(
                        Icons.auto_stories_rounded,
                        size: 72,
                        color: scheme.onPrimary.withValues(alpha: 0.14),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: Gap.lg,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(Gap.xs),
                  decoration: BoxDecoration(color: theme.scaffoldBackgroundColor, shape: BoxShape.circle),
                  child: UserAvatar(name: profile.displayName, url: profile.avatarUrl, radius: 48),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(profile.displayName, style: theme.textTheme.headlineSmall),
              Text('@${profile.username}', style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              if (bio != null && bio.isNotEmpty) ...[Gap.h8, Text(bio, style: theme.textTheme.bodyMedium)],
              if (district != null && district.isNotEmpty) ...[
                Gap.h8,
                Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 18, color: scheme.onSurfaceVariant),
                    Gap.w4,
                    Text(district, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ],
              Gap.h16,
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.md),
                  child: Row(
                    children: [
                      _Stat(
                        value: Fmt.count(profile.friendsCount, bangla: bn),
                        label: l.friendsStatFriends,
                      ),
                      _Stat(
                        value: Fmt.count(profile.postsCount, bangla: bn),
                        label: l.friendsStatPosts,
                      ),
                      _Stat(
                        value: Fmt.count(profile.examsTaken, bangla: bn),
                        label: l.friendsStatExams,
                      ),
                      _Stat(
                        value: Fmt.count(profile.streakCount, bangla: bn),
                        label: l.friendsStatStreak,
                        icon: Icons.local_fire_department_rounded,
                      ),
                    ],
                  ),
                ),
              ),
              Gap.h16,
              if (isMe)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () => unawaited(context.push(Routes.editProfile)),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(l.friendsEditProfile),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: RelationshipButton(userId: profile.id, displayName: profile.displayName, expanded: true),
                    ),
                    if (!blocked) ...[
                      Gap.w8,
                      OutlinedButton.icon(
                        onPressed: () => unawaited(openDirectChat(context, ref, profile.id)),
                        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                        label: Text(l.friendsMessage),
                      ),
                    ],
                  ],
                ),
              if (blocked) ...[
                Gap.h12,
                Card(
                  color: scheme.errorContainer.withValues(alpha: 0.5),
                  child: Padding(
                    padding: Gap.card,
                    child: Row(
                      children: [
                        Icon(Icons.block_rounded, color: scheme.onErrorContainer),
                        Gap.w12,
                        Expanded(
                          child: Text(
                            l.friendsBlockedNotice,
                            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onErrorContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                Gap.h24,
                Text(l.friendsPostsHeader, style: theme.textTheme.titleMedium),
              ],
              Gap.h8,
            ],
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.icon});

  final String value;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Semantics(
        label: '$value $label',
        excludeSemantics: true,
        child: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) Icon(icon, size: 18, color: theme.colorScheme.secondary),
                Text(value, style: theme.textTheme.titleLarge),
              ],
            ),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(height: 104, radius: 0),
          Padding(
            padding: EdgeInsets.all(Gap.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 96, height: 96, radius: 48),
                Gap.h16,
                SkeletonBox(width: 180, height: 20),
                Gap.h8,
                SkeletonBox(width: 120),
                Gap.h16,
                SkeletonBox(height: 72, radius: 16),
                Gap.h16,
                SkeletonBox(height: 44, radius: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
