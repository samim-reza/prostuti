import 'package:flutter/foundation.dart';
import 'package:prostuti/core/errors/failure.dart';

/// One page from a keyset-paginated endpoint. [nextCursor] is null on the
/// last page.
@immutable
class PageResult<T, C> {
  const PageResult(this.items, this.nextCursor);
  final List<T> items;
  final C? nextCursor;
}

/// Immutable state of an infinite list.
@immutable
class PagedState<T, C> {
  const PagedState({
    this.items = const [],
    this.cursor,
    this.hasMore = true,
    this.isLoadingFirst = true,
    this.isLoadingMore = false,
    this.error,
  });

  final List<T> items;
  final C? cursor;
  final bool hasMore;
  final bool isLoadingFirst;
  final bool isLoadingMore;
  final AppFailure? error;

  bool get isEmpty => !isLoadingFirst && items.isEmpty && error == null;

  PagedState<T, C> copyWith({
    List<T>? items,
    C? cursor,
    bool clearCursor = false,
    bool? hasMore,
    bool? isLoadingFirst,
    bool? isLoadingMore,
    AppFailure? error,
    bool clearError = false,
  }) => PagedState<T, C>(
    items: items ?? this.items,
    cursor: clearCursor ? null : (cursor ?? this.cursor),
    hasMore: hasMore ?? this.hasMore,
    isLoadingFirst: isLoadingFirst ?? this.isLoadingFirst,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    error: clearError ? null : (error ?? this.error),
  );
}
