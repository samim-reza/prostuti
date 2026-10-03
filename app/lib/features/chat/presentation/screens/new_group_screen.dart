import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:prostuti/features/chat/presentation/widgets/start_chat_sheet.dart';
import 'package:prostuti/features/profile/data/profile.dart';

/// Create a group: name + multi-select friends (with search).
class NewGroupScreen extends ConsumerStatefulWidget {
  const NewGroupScreen({super.key});

  @override
  ConsumerState<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends ConsumerState<NewGroupScreen> {
  static const _maxTitle = 80;

  final _title = TextEditingController();
  final _debouncer = Debouncer(const Duration(milliseconds: 180));

  /// Insertion-ordered so chips appear in the order friends were picked.
  final _selected = <String, UserSummary>{};
  String _query = '';
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    registerChatFailureMessages();
    _title.addListener(_onTitle);
  }

  @override
  void dispose() {
    _title
      ..removeListener(_onTitle)
      ..dispose();
    _debouncer.dispose();
    super.dispose();
  }

  void _onTitle() => setState(() {});

  void _toggle(UserSummary f) {
    final l = context.l10n;
    setState(() {
      if (_selected.remove(f.id) == null) {
        if (_selected.length >= ChatRepository.maxGroupMembers) {
          showInfoSnack(context, l.chatGroupMaxMembers(context.n(ChatRepository.maxGroupMembers)));
          return;
        }
        _selected[f.id] = f;
      }
    });
  }

  Future<void> _create() async {
    final l = context.l10n;
    final title = _title.text.trim();
    if (title.isEmpty) {
      showInfoSnack(context, l.chatGroupNeedName);
      return;
    }
    if (_selected.isEmpty) {
      showInfoSnack(context, l.chatGroupNeedMembers);
      return;
    }
    if (!ConnectivityService.instance.isOnline) {
      showInfoSnack(context, l.offlineUnavailable);
      return;
    }
    setState(() => _creating = true);
    try {
      final id = await ref.read(chatRepositoryProvider).createGroup(title, _selected.keys.toList());
      if (!mounted) return;
      if (ref.exists(conversationListProvider)) unawaited(ref.read(conversationListProvider.notifier).refresh());
      context.pushReplacement(Routes.chat(id));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      showChatError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final friends = ref.watch(chatFriendsProvider);
    final canCreate = _title.text.trim().isNotEmpty && _selected.isNotEmpty && !_creating;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.chatNewGroup),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Gap.sm),
            child: _creating
                ? const Padding(
                    padding: EdgeInsets.all(Gap.md),
                    child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
                  )
                : FilledButton(
                    onPressed: canCreate ? () => unawaited(_create()) : null,
                    style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
                    child: Text(l.chatCreateGroup),
                  ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, 0),
            child: TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              inputFormatters: [LengthLimitingTextInputFormatter(_maxTitle)],
              decoration: InputDecoration(
                labelText: l.chatGroupNameLabel,
                hintText: l.chatGroupNameHint,
                prefixIcon: const Icon(Icons.groups_rounded),
                counterText: '${context.n(_title.text.characters.length)}/${context.n(_maxTitle)}',
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            child: _selected.isEmpty
                ? const SizedBox(width: double.infinity)
                : SizedBox(
                    height: 52,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.xs),
                      children: [
                        for (final f in _selected.values)
                          Padding(
                            padding: const EdgeInsets.only(right: Gap.sm),
                            child: InputChip(
                              avatar: UserAvatar(name: f.displayName, url: f.avatarUrl, radius: 12),
                              label: Text(f.displayName),
                              deleteButtonTooltipMessage: l.chatRemoveSelection,
                              onDeleted: () => _toggle(f),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.xs),
            child: Row(
              children: [
                Text(l.chatSelectMembers, style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(
                  l.chatSelectedCount(context.n(_selected.length)),
                  style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
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
              error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(chatFriendsProvider)),
              data: (all) {
                if (all.isEmpty) {
                  return EmptyView(
                    icon: Icons.people_outline_rounded,
                    title: l.chatNoFriendsTitle,
                    message: l.chatNoFriendsMessage,
                    actionLabel: l.chatFindFriends,
                    action: () => context.push(Routes.userSearch).ignore(),
                  );
                }
                final list = filterFriends(all, _query);
                if (list.isEmpty) return EmptyView(icon: Icons.search_off_rounded, title: l.chatNoFriendsMatch);
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: Gap.xl),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final f = list[i];
                    final selected = _selected.containsKey(f.id);
                    return CheckboxListTile(
                      key: ValueKey(f.id),
                      value: selected,
                      onChanged: _creating ? null : (_) => _toggle(f),
                      controlAffinity: ListTileControlAffinity.trailing,
                      secondary: UserAvatar(name: f.displayName, url: f.avatarUrl, radius: 22),
                      title: Text(f.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('@${f.username}', maxLines: 1, overflow: TextOverflow.ellipsis),
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
