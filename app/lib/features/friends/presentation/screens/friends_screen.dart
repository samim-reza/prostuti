import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/pagination/paged_state.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/paged_list_view.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/friends/application/friends_controller.dart';
import 'package:prostuti/features/friends/data/friend_models.dart';
import 'package:prostuti/features/friends/presentation/widgets/relationship_button.dart';
import 'package:prostuti/features/friends/presentation/widgets/user_tile.dart';

/// Friends · Requests · People you may know.
class FriendsScreen extends ConsumerWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final pending = ref.watch(incomingRequestCountProvider.select((v) => v.value ?? 0));
    return DefaultTabController(
      length: 3,
      initialIndex: pending > 0 ? 1 : 0,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.friendsTitle),
          actions: [
            IconButton(
              tooltip: l.friendsFindPeople,
              icon: const Icon(Icons.person_search_outlined),
              onPressed: () => unawaited(context.push(Routes.userSearch)),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: l.friendsTabFriends),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l.friendsTabRequests),
                    if (pending > 0) ...[Gap.w8, Badge(label: Text(context.n(pending)))],
                  ],
                ),
              ),
              Tab(text: l.friendsTabSuggestions),
            ],
          ),
        ),
        body: const TabBarView(children: [_FriendsTab(), _RequestsTab(), _SuggestionsTab()]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Friends
// ---------------------------------------------------------------------------

class _FriendsTab extends ConsumerWidget {
  const _FriendsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final state = ref.watch(friendsListProvider);
    final notifier = ref.read(friendsListProvider.notifier);
    return PagedListView<Friend>(
      state: state,
      onLoadMore: () => unawaited(notifier.loadMore()),
      onRefresh: notifier.refresh,
      onRetry: () => unawaited(notifier.retry()),
      empty: EmptyView(
        icon: Icons.people_outline_rounded,
        title: l.friendsEmptyTitle,
        message: l.friendsEmptyBody,
        action: () => unawaited(context.push(Routes.userSearch)),
        actionLabel: l.friendsFindPeople,
      ),
      itemBuilder: (context, friend, _) => UserTile(
        key: ValueKey(friend.user.id),
        user: friend.user,
        subtitle: (friend.bio?.trim().isNotEmpty ?? false)
            ? friend.bio!.trim()
            : l.friendsSince(Fmt.date(friend.friendsSince, bangla: context.isBn)),
        trailing: RelationshipButton(userId: friend.user.id, displayName: friend.user.displayName),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Requests (incoming + sent)
// ---------------------------------------------------------------------------

class _RequestsTab extends ConsumerWidget {
  const _RequestsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final incoming = ref.watch(friendRequestsProvider(true));
    final outgoing = ref.watch(friendRequestsProvider(false));
    if (incoming.isLoadingFirst && incoming.items.isEmpty) return const SkeletonList();

    Future<void> refresh() async {
      ref.invalidate(incomingRequestCountProvider);
      await Future.wait([
        ref.read(friendRequestsProvider(true).notifier).refresh(),
        ref.read(friendRequestsProvider(false).notifier).refresh(),
      ]);
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          _SectionHeader(title: l.friendsIncoming, count: incoming.items.length, hasMore: incoming.hasMore),
          ..._requestSection(
            context,
            ref,
            state: incoming,
            incoming: true,
            empty: EmptyView(
              compact: true,
              icon: Icons.mark_email_read_outlined,
              title: l.friendsNoRequests,
              message: l.friendsNoRequestsBody,
            ),
          ),
          _SectionHeader(title: l.friendsOutgoing, count: outgoing.items.length, hasMore: outgoing.hasMore),
          ..._requestSection(
            context,
            ref,
            state: outgoing,
            incoming: false,
            empty: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.sm),
              child: Text(
                l.friendsNoOutgoing,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: Gap.h32),
        ],
      ),
    );
  }

  List<Widget> _requestSection(
    BuildContext context,
    WidgetRef ref, {
    required PagedState<FriendRequest, DateTime> state,
    required bool incoming,
    required Widget empty,
  }) {
    final l = context.l10n;
    final notifier = ref.read(friendRequestsProvider(incoming).notifier);
    if (state.error != null && state.items.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: ErrorView(error: state.error!, compact: true, onRetry: () => unawaited(notifier.retry())),
        ),
      ];
    }
    if (state.isLoadingFirst && state.items.isEmpty) {
      return const [SliverToBoxAdapter(child: SkeletonList(itemCount: 2))];
    }
    if (state.items.isEmpty) return [SliverToBoxAdapter(child: empty)];
    return [
      SliverList.builder(
        itemCount: state.items.length,
        itemBuilder: (context, i) {
          final r = state.items[i];
          return UserTile(
            key: ValueKey(r.id),
            user: r.user,
            subtitle: [
              if (r.mutualFriends > 0) l.friendsMutual(context.n(r.mutualFriends)),
              Fmt.timeAgo(r.createdAt, bangla: context.isBn),
            ].join(' · '),
            avatarRadius: 28,
            bottom: RelationshipButton(userId: r.user.id, displayName: r.user.displayName, expanded: true),
          );
        },
      ),
      if (state.hasMore)
        SliverToBoxAdapter(
          child: Center(
            child: state.isLoadingMore
                ? const Padding(
                    padding: EdgeInsets.all(Gap.md),
                    child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
                  )
                : TextButton(
                    onPressed: () => unawaited(state.error != null ? notifier.retry() : notifier.loadMore()),
                    child: Text(state.error != null ? l.retry : l.friendsLoadMore),
                  ),
          ),
        ),
    ];
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count, required this.hasMore});

  final String title;
  final int count;
  final bool hasMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.xs),
        child: Row(
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            if (count > 0) ...[
              Gap.w8,
              Text(
                hasMore ? '${context.n(count)}+' : context.n(count),
                style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// People you may know
// ---------------------------------------------------------------------------

class _SuggestionsTab extends ConsumerWidget {
  const _SuggestionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final suggestions = ref.watch(suggestionsProvider);
    final notifier = ref.read(suggestionsProvider.notifier);
    return AsyncView<List<FriendSuggestion>>(
      value: suggestions,
      onRetry: () => ref.invalidate(suggestionsProvider),
      isEmpty: (list) => list.isEmpty,
      empty: RefreshIndicator(
        onRefresh: notifier.refresh,
        child: ListView(
          children: [
            EmptyView(
              icon: Icons.diversity_3_outlined,
              title: l.friendsNoSuggestions,
              message: l.friendsNoSuggestionsBody,
              action: () => unawaited(context.push(Routes.editProfile)),
              actionLabel: l.friendsEditProfile,
            ),
          ],
        ),
      ),
      data: (list) => RefreshIndicator(
        onRefresh: notifier.refresh,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: Gap.sm),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final s = list[i];
            return UserTile(
              key: ValueKey(s.user.id),
              user: s.user,
              avatarRadius: 28,
              subtitle: userSubtitle(s.user, district: s.district),
              extra: _ReasonChips(suggestion: s),
              bottom: Row(
                children: [
                  Expanded(
                    child: RelationshipButton(userId: s.user.id, displayName: s.user.displayName, expanded: true),
                  ),
                  Gap.w8,
                  Expanded(
                    child: TextButton(
                      onPressed: () => notifier.dismiss(s.user.id),
                      child: Text(l.friendsRemoveSuggestion),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ReasonChips extends StatelessWidget {
  const _ReasonChips({required this.suggestion});

  final FriendSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, label) = switch (suggestion.reason) {
      SuggestionReason.mutual => (Icons.people_alt_rounded, l.friendsReasonMutual),
      SuggestionReason.district => (Icons.location_on_rounded, l.friendsReasonDistrict),
      SuggestionReason.sameExam => (Icons.school_rounded, l.friendsReasonSameExam),
      SuggestionReason.newcomer => (Icons.fiber_new_rounded, l.friendsReasonNew),
    };
    Widget chip(IconData icon, String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.xxs),
      decoration: BoxDecoration(color: scheme.secondaryContainer.withValues(alpha: 0.7), borderRadius: Radii.chip),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSecondaryContainer),
          Gap.w4,
          Text(text, style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSecondaryContainer)),
        ],
      ),
    );
    return Wrap(
      spacing: Gap.xs,
      runSpacing: Gap.xs,
      children: [
        chip(icon, label),
        if (suggestion.mutualFriends > 0 && suggestion.reason != SuggestionReason.mutual)
          chip(Icons.people_alt_rounded, l.friendsMutual(context.n(suggestion.mutualFriends)))
        else if (suggestion.mutualFriends > 0)
          Text(
            l.friendsMutual(context.n(suggestion.mutualFriends)),
            style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
      ],
    );
  }
}
