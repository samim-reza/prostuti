import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/rate_limit/debouncer.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/app_image.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/chat/application/conversation_list_controller.dart';
import 'package:prostuti/features/chat/data/chat_repository.dart';
import 'package:prostuti/features/chat/presentation/widgets/chat_errors.dart';
import 'package:prostuti/features/profile/data/profile.dart';

/// Bottom sheet: "new group" entry + friends list to start a direct chat.
Future<void> showStartChatSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => const StartChatSheet(),
);

/// Case-insensitive match on name or username.
List<UserSummary> filterFriends(List<UserSummary> friends, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return friends;
  return [
    for (final f in friends)
      if (f.displayName.toLowerCase().contains(q) || f.username.toLowerCase().contains(q)) f,
  ];
}

class StartChatSheet extends ConsumerStatefulWidget {
  const StartChatSheet({super.key});

  @override
  ConsumerState<StartChatSheet> createState() => _StartChatSheetState();
}

class _StartChatSheetState extends ConsumerState<StartChatSheet> {
  final _debouncer = Debouncer(const Duration(milliseconds: 180));
  String _query = '';
  String? _opening;

  @override
  void dispose() {
    _debouncer.dispose();
    super.dispose();
  }

  Future<void> _open(UserSummary friend) async {
    if (_opening != null) return;
    final l = context.l10n;
    if (!ConnectivityService.instance.isOnline) {
      showInfoSnack(context, l.offlineUnavailable);
      return;
    }
    final router = GoRouter.of(context);
    final navigator = Navigator.of(context);
    setState(() => _opening = friend.id);
    try {
      final id = await ref.read(chatRepositoryProvider).openDirect(friend.id);
      if (!mounted) return;
      navigator.pop();
      await router.push(Routes.chat(id));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _opening = null);
      showChatError(context, e);
    }
  }

  void _newGroup() {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push(Routes.newGroup).ignore();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final friends = ref.watch(chatFriendsProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.md),
            child: Row(children: [Text(l.chatStartSheetTitle, style: theme.textTheme.titleLarge)]),
          ),
          Padding(
            padding: Gap.screen,
            child: TextField(
              textInputAction: TextInputAction.search,
              onChanged: (v) => _debouncer(() {
                if (mounted) setState(() => _query = v);
              }),
              decoration: InputDecoration(
                hintText: l.chatStartSearchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
              ),
            ),
          ),
          Gap.h8,
          Expanded(
            child: friends.when(
              skipLoadingOnRefresh: true,
              loading: () => const SkeletonList(),
              error: (e, _) => ErrorView(error: e, compact: true, onRetry: () => ref.invalidate(chatFriendsProvider)),
              data: (all) {
                final list = filterFriends(all, _query);
                return ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.only(bottom: Gap.xl),
                  itemCount: list.length + 2,
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return ListTile(
                        minTileHeight: 64,
                        leading: CircleAvatar(
                          radius: 22,
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Icon(Icons.group_add_rounded, color: theme.colorScheme.onPrimaryContainer),
                        ),
                        title: Text(l.chatNewGroup, style: theme.textTheme.titleSmall),
                        subtitle: Text(l.chatNewGroupSubtitle),
                        onTap: _newGroup,
                      );
                    }
                    if (i == 1) {
                      if (all.isEmpty) {
                        return EmptyView(
                          compact: true,
                          icon: Icons.people_outline_rounded,
                          title: l.chatNoFriendsTitle,
                          message: l.chatNoFriendsMessage,
                          actionLabel: l.chatFindFriends,
                          action: () {
                            final router = GoRouter.of(context);
                            Navigator.of(context).pop();
                            router.push(Routes.userSearch).ignore();
                          },
                        );
                      }
                      if (list.isEmpty) {
                        return EmptyView(compact: true, icon: Icons.search_off_rounded, title: l.chatNoFriendsMatch);
                      }
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.xs),
                        child: Text(
                          l.chatFriendsHeader,
                          style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      );
                    }
                    final f = list[i - 2];
                    return ListTile(
                      key: ValueKey(f.id),
                      minTileHeight: 60,
                      leading: UserAvatar(name: f.displayName, url: f.avatarUrl, radius: 22),
                      title: Text(f.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('@${f.username}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: _opening == f.id
                          ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                          : Icon(Icons.chat_bubble_outline_rounded, color: theme.colorScheme.primary),
                      onTap: () => _open(f),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
