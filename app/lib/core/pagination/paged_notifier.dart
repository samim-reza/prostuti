import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/pagination/paged_state.dart';

/// Base class for every infinite list (feed, comments, chats, notifications…).
///
/// Subclasses implement [fetchPage] (keyset/cursor based — never OFFSET, so
/// page N costs the same as page 1) and [idOf] (used to de-duplicate items
/// when realtime inserts and pagination overlap).
abstract class PagedNotifier<T, C> extends Notifier<PagedState<T, C>> {
  bool _busy = false;

  Future<PageResult<T, C>> fetchPage(C? cursor);

  Object idOf(T item);

  /// Optional instant first paint from cache (stale-while-revalidate).
  List<T>? readCachedFirstPage() => null;

  @override
  PagedState<T, C> build() {
    final cached = readCachedFirstPage();
    unawaited(Future.microtask(refresh));
    if (cached != null && cached.isNotEmpty) {
      return PagedState<T, C>(items: cached, isLoadingFirst: false);
    }
    return PagedState<T, C>();
  }

  /// Reloads from the first page (pull-to-refresh).
  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    state = state.copyWith(isLoadingFirst: state.items.isEmpty, clearError: true);
    try {
      final page = await fetchPage(null);
      if (!ref.mounted) return;
      state = PagedState<T, C>(
        items: page.items,
        cursor: page.nextCursor,
        hasMore: page.nextCursor != null,
        isLoadingFirst: false,
      );
      onFirstPageLoaded(page.items);
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(isLoadingFirst: false, error: AppFailure.from(e));
    } finally {
      _busy = false;
    }
  }

  /// Loads the next page; safe to call repeatedly from scroll listeners.
  Future<void> loadMore() async {
    if (_busy || !state.hasMore || state.isLoadingFirst || state.error != null) return;
    _busy = true;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await fetchPage(state.cursor);
      if (!ref.mounted) return;
      state = state.copyWith(
        items: _merge(state.items, page.items),
        cursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
        hasMore: page.nextCursor != null,
        isLoadingMore: false,
      );
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(isLoadingMore: false, error: AppFailure.from(e));
    } finally {
      _busy = false;
    }
  }

  /// Retries after an error (first page or next page).
  Future<void> retry() {
    if (state.items.isEmpty) return refresh();
    state = state.copyWith(clearError: true);
    return loadMore();
  }

  /// Hook for caching the first page.
  void onFirstPageLoaded(List<T> items) {}

  /// Inserts/replaces an item at the top (optimistic create, realtime insert).
  void upsertFirst(T item) {
    final id = idOf(item);
    final rest = state.items.where((e) => idOf(e) != id);
    state = state.copyWith(items: [item, ...rest]);
  }

  /// Replaces an item in place if present.
  void replace(T item) {
    final id = idOf(item);
    state = state.copyWith(
      items: [
        for (final e in state.items)
          if (idOf(e) == id) item else e,
      ],
    );
  }

  void removeWhere(bool Function(T item) test) {
    state = state.copyWith(items: state.items.where((e) => !test(e)).toList());
  }

  /// O(n + m) merge that drops duplicates using a hash set of ids.
  List<T> _merge(List<T> current, List<T> next) {
    final seen = <Object>{for (final e in current) idOf(e)};
    return [...current, ...next.where((e) => seen.add(idOf(e)))];
  }
}
