import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/app_image.dart';
import 'package:prostuti/core/widgets/paged_list_view.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/settings/application/blocked_users_controller.dart';
import 'package:prostuti/features/settings/data/settings_repository.dart';

class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final state = ref.watch(blockedUsersProvider);
    final notifier = ref.read(blockedUsersProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(l.settingsBlockedUsers)),
      body: PagedListView<BlockedUser>(
        state: state,
        onLoadMore: () => unawaited(notifier.loadMore()),
        onRefresh: notifier.refresh,
        onRetry: () => unawaited(notifier.retry()),
        header: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.sm),
          child: Text(
            l.settingsBlockedIntro,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        empty: EmptyView(
          icon: Icons.shield_outlined,
          title: l.settingsBlockedEmpty,
          message: l.settingsBlockedEmptyHint,
        ),
        separator: const Divider(indent: 72),
        itemBuilder: (context, user, _) => _BlockedTile(user: user),
      ),
    );
  }
}

class _BlockedTile extends ConsumerWidget {
  const _BlockedTile({required this.user});
  final BlockedUser user;

  Future<void> _unblock(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    if (!ConnectivityService.instance.isOnline) {
      showInfoSnack(context, l.offlineUnavailable);
      return;
    }
    final ok = await confirmDialog(
      context,
      title: l.settingsUnblockTitle(user.displayName),
      message: l.settingsUnblockBody,
      confirmLabel: l.settingsUnblock,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(blockedUsersProvider.notifier).unblock(user);
      if (context.mounted) showInfoSnack(context, l.settingsUnblocked(user.displayName));
    } on Object catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.xs),
      leading: UserAvatar(name: user.displayName, url: user.avatarUrl, radius: 22),
      title: Text(user.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '@${user.username} · ${l.settingsBlockedAgo(Fmt.timeAgo(user.blockedAt, bangla: context.isBn))}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      onTap: () => unawaited(context.push(Routes.userProfile(user.id))),
      trailing: OutlinedButton(
        onPressed: () => unawaited(_unblock(context, ref)),
        style: OutlinedButton.styleFrom(minimumSize: const Size(88, 40)),
        child: Text(l.settingsUnblock),
      ),
    );
  }
}
