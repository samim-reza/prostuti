import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/app_image.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/addons/application/addons_providers.dart';
import 'package:prostuti/features/profile/data/bd_districts.dart';
import 'package:prostuti/features/profile/data/profile.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';
import 'package:prostuti/features/profile/presentation/widgets/premium_status_card.dart';
import 'package:prostuti/features/settings/presentation/logout.dart';

/// Profile tab: who I am, my numbers, my plan and every account shortcut.
class MyProfileScreen extends ConsumerWidget {
  const MyProfileScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    await Future.wait([ref.read(currentProfileProvider.notifier).reload(), refreshStore(ref)]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final async = ref.watch(currentProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.navProfile),
        actions: [
          IconButton(
            tooltip: l.profileSettings,
            onPressed: () => unawaited(context.push(Routes.settings)),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: async.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const _ProfileSkeleton(),
        error: (e, _) =>
            ErrorView(error: e, onRetry: () => unawaited(ref.read(currentProfileProvider.notifier).reload())),
        data: (profile) => profile == null
            ? const _ProfileSkeleton()
            : RefreshIndicator(
                onRefresh: () => _refresh(ref),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl),
                  children: [
                    _Header(profile: profile),
                    Gap.h16,
                    _StatsRow(profile: profile),
                    Gap.h16,
                    const PremiumStatusCard(),
                    Gap.h16,
                    _Menu(profile: profile),
                  ],
                ),
              ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.profile});
  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final district = districtLabel(profile.district, bangla: context.isBn);
    final bio = profile.bio?.trim();

    return Card(
      child: Padding(
        padding: Gap.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(name: profile.displayName, url: profile.avatarUrl, radius: 36),
                Gap.w16,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              profile.displayName,
                              style: theme.textTheme.titleLarge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (profile.isStaff) ...[
                            Gap.w4,
                            Tooltip(
                              message: profile.isAdmin ? l.profileRoleAdmin : l.profileRoleModerator,
                              child: Icon(Icons.verified_user_rounded, size: 18, color: scheme.primary),
                            ),
                          ],
                        ],
                      ),
                      if (profile.username.isNotEmpty)
                        Text(
                          '@${profile.username}',
                          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      if (district != null || profile.occupation != null) ...[
                        Gap.h4,
                        Wrap(
                          spacing: Gap.md,
                          runSpacing: Gap.xxs,
                          children: [
                            if (district != null) _Meta(icon: Icons.place_outlined, text: district),
                            if (profile.occupation?.trim().isNotEmpty ?? false)
                              _Meta(icon: Icons.work_outline_rounded, text: profile.occupation!.trim()),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (bio != null && bio.isNotEmpty) ...[Gap.h12, Text(bio, style: theme.textTheme.bodyMedium)],
            Gap.h12,
            OutlinedButton.icon(
              onPressed: () => unawaited(context.push(Routes.editProfile)),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(l.profileEdit),
            ),
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        Gap.w4,
        Text(text, style: theme.textTheme.bodySmall?.copyWith(color: color)),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.profile});
  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final bangla = context.isBn;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.sm),
        child: Row(
          children: [
            _Stat(
              value: Fmt.count(profile.friendsCount, bangla: bangla),
              label: l.profileStatFriends,
              onTap: () => context.push(Routes.friends),
            ),
            _Stat(
              value: Fmt.count(profile.postsCount, bangla: bangla),
              label: l.profileStatPosts,
              onTap: () => context.push(Routes.userProfile(profile.id)),
            ),
            _Stat(
              value: Fmt.count(profile.examsTaken, bangla: bangla),
              label: l.profileStatExams,
              onTap: () => context.push(Routes.examHistory),
            ),
            _Stat(
              value: Fmt.count(profile.streakCount, bangla: bangla),
              label: l.profileStatStreak,
              icon: Icons.local_fire_department_rounded,
              iconColor: AppColors.warning,
              tooltip: l.profileLongestStreak(context.n(profile.longestStreak)),
              onTap: () => context.push(Routes.progress),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.onTap, this.icon, this.iconColor, this.tooltip});

  final String value;
  final String label;
  final IconData? icon;
  final Color? iconColor;
  final String? tooltip;
  final Future<Object?> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget child = InkWell(
      borderRadius: Radii.button,
      onTap: () => unawaited(onTap()),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) Icon(icon, size: 18, color: iconColor),
                  Text(value, style: theme.textTheme.titleLarge),
                ],
              ),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
    if (tooltip != null) child = Tooltip(message: tooltip, child: child);
    return Expanded(
      child: Semantics(button: true, label: '$value $label', excludeSemantics: true, child: child),
    );
  }
}

class _Menu extends ConsumerWidget {
  const _Menu({required this.profile});
  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final activity = [
      _MenuItem(Icons.dynamic_feed_outlined, l.profileMenuMyPosts, Routes.userProfile(profile.id)),
      _MenuItem(Icons.group_outlined, l.profileMenuFriends, Routes.friends),
      _MenuItem(Icons.bookmarks_outlined, l.profileMenuBookmarks, Routes.bookmarks),
      _MenuItem(Icons.history_rounded, l.profileMenuExamHistory, Routes.examHistory),
      _MenuItem(Icons.insights_outlined, l.profileMenuProgress, Routes.progress),
      _MenuItem(Icons.event_note_outlined, l.profileMenuPlan, Routes.plan),
    ];
    final account = [
      _MenuItem(Icons.workspace_premium_outlined, l.profileMenuAddons, Routes.addons),
      _MenuItem(Icons.settings_outlined, l.profileMenuSettings, Routes.settings),
      if (profile.isStaff) _MenuItem(Icons.admin_panel_settings_outlined, l.profileMenuAdmin, Routes.admin),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MenuCard(title: l.profileSectionActivity, items: activity),
        Gap.h16,
        _MenuCard(title: l.profileSectionAccount, items: account),
        Gap.h16,
        Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: Icon(Icons.logout_rounded, color: scheme.error),
            title: Text(l.profileMenuLogout, style: TextStyle(color: scheme.error)),
            onTap: () => unawaited(confirmAndSignOut(context, ref)),
          ),
        ),
      ],
    );
  }
}

class _MenuItem {
  const _MenuItem(this.icon, this.label, this.route);
  final IconData icon;
  final String label;
  final String route;
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.title, required this.items});
  final String title;
  final List<_MenuItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: Gap.xs, bottom: Gap.sm),
          child: Text(title, style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary)),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const Divider(indent: 56),
                ListTile(
                  leading: Icon(items[i].icon, color: scheme.primary),
                  title: Text(items[i].label),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => unawaited(context.push(items[i].route)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Gap.lg),
        children: const [
          Row(
            children: [
              SkeletonBox(width: 72, height: 72, radius: 36),
              Gap.w16,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [SkeletonBox(width: 160, height: 18), Gap.h8, SkeletonBox(width: 100)],
                ),
              ),
            ],
          ),
          Gap.h24,
          SkeletonBox(height: 72, radius: 16),
          Gap.h16,
          SkeletonBox(height: 96, radius: 16),
          Gap.h16,
          SkeletonBox(height: 280, radius: 16),
        ],
      ),
    );
  }
}
