import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/pagination/paged_notifier.dart';
import 'package:prostuti/core/pagination/paged_state.dart';
import 'package:prostuti/features/friends/application/relationship_controller.dart';
import 'package:prostuti/features/friends/data/relationship.dart';
import 'package:prostuti/features/settings/data/settings_repository.dart';

class BlockedUsersNotifier extends PagedNotifier<BlockedUser, DateTime> {
  @override
  Future<PageResult<BlockedUser, DateTime>> fetchPage(DateTime? cursor) =>
      ref.read(settingsRepositoryProvider).blockedPage(cursor);

  @override
  Object idOf(BlockedUser item) => item.id;

  @override
  List<BlockedUser>? readCachedFirstPage() => ref.read(settingsRepositoryProvider).readCachedBlocked();

  @override
  void onFirstPageLoaded(List<BlockedUser> items) =>
      unawaited(ref.read(settingsRepositoryProvider).writeCachedBlocked(items));

  /// Optimistic unblock: the row disappears at once and comes back (in the
  /// same position) if the server call fails.
  Future<void> unblock(BlockedUser user) async {
    final index = state.items.indexWhere((u) => u.id == user.id);
    if (index < 0) return;
    removeWhere((u) => u.id == user.id);
    final repo = ref.read(settingsRepositoryProvider);
    final seeds = ref.read(relationshipSeedsProvider);
    try {
      await repo.unblock(user.id);
      // Seeds are app-scoped, so their profile stops showing "blocked" even
      // if this list was closed meanwhile.
      seeds.put(user.id, Relationship.none);
      if (ref.mounted) {
        ref.invalidate(relationshipProvider(user.id));
        unawaited(repo.writeCachedBlocked(state.items));
      }
    } on Object {
      if (ref.mounted) {
        final items = [...state.items]..insert(index.clamp(0, state.items.length), user);
        state = state.copyWith(items: items);
      }
      rethrow;
    }
  }
}

final blockedUsersProvider = NotifierProvider.autoDispose<BlockedUsersNotifier, PagedState<BlockedUser, DateTime>>(
  BlockedUsersNotifier.new,
);
