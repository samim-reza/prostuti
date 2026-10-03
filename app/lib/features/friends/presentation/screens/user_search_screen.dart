import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/feed/l10n/social_failures.dart';
import 'package:prostuti/features/friends/application/friends_controller.dart';
import 'package:prostuti/features/friends/presentation/widgets/relationship_button.dart';
import 'package:prostuti/features/friends/presentation/widgets/user_tile.dart';

/// Debounced people search with relationship-aware buttons. Needs the network.
class UserSearchScreen extends ConsumerStatefulWidget {
  const UserSearchScreen({super.key});

  @override
  ConsumerState<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends ConsumerState<UserSearchScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    ref.read(userSearchProvider.notifier).onQueryChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final state = ref.watch(userSearchProvider);
    final notifier = ref.read(userSearchProvider.notifier);
    final online = ref.watch(isOnlineProvider.select((v) => v.value ?? ConnectivityService.instance.isOnline));
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: notifier.onQueryChanged,
          onSubmitted: notifier.onQueryChanged,
          decoration: InputDecoration(
            hintText: l.friendsSearchHint,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
          ),
        ),
        actions: [
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(tooltip: l.friendsClearSearch, icon: const Icon(Icons.close_rounded), onPressed: _clear),
          ),
        ],
      ),
      body: _body(context, state, online: online),
    );
  }

  Widget _body(BuildContext context, UserSearchState state, {required bool online}) {
    final l = context.l10n;
    if (state.tooShort) {
      return EmptyView(
        icon: online ? Icons.person_search_outlined : Icons.wifi_off_rounded,
        title: online ? l.friendsSearchPromptTitle : l.offlineUnavailable,
        message: online ? l.friendsSearchPromptBody : null,
      );
    }
    return state.results.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => const SkeletonList(itemCount: 5),
      error: (e, _) {
        if (AppFailure.from(e) is NetworkFailure) {
          return EmptyView(
            icon: Icons.wifi_off_rounded,
            title: l.offlineUnavailable,
            action: () => ref.read(userSearchProvider.notifier).retry(),
            actionLabel: l.retry,
          );
        }
        return EmptyView(
          icon: Icons.cloud_off_rounded,
          title: l.errorGeneric,
          message: socialErrorMessage(context, e),
          action: () => ref.read(userSearchProvider.notifier).retry(),
          actionLabel: l.retry,
        );
      },
      data: (results) {
        if (results.isEmpty) {
          return EmptyView(
            icon: Icons.search_off_rounded,
            title: l.friendsSearchNoResults,
            message: l.friendsSearchNoResultsBody(state.query),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: Gap.sm),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: results.length,
          itemBuilder: (context, i) {
            final r = results[i];
            return UserTile(
              key: ValueKey(r.user.id),
              user: r.user,
              subtitle: userSubtitle(r.user, district: r.district),
              trailing: RelationshipButton(userId: r.user.id, displayName: r.user.displayName),
            );
          },
        );
      },
    );
  }
}
