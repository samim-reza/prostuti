import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/pagination/paged_notifier.dart';
import 'package:prostuti/core/pagination/paged_state.dart';
import 'package:prostuti/features/bookmarks/data/bookmark.dart';
import 'package:prostuti/features/bookmarks/data/bookmarks_repository.dart';

/// One tab of the bookmarks screen. The first page is cached on disk (instant
/// paint, offline reading); removals are optimistic and survive offline.
class BookmarksNotifier extends PagedNotifier<Bookmark, BookmarkCursor> {
  BookmarksNotifier(this.type);

  final BookmarkType type;

  BookmarksRepository get _repo => ref.read(bookmarksRepositoryProvider);

  List<Bookmark> _withoutPending(List<Bookmark> items) {
    final pending = BookmarksRepository.pendingRemovals();
    if (pending.isEmpty) return items;
    return items.where((b) => !pending.contains(b.key)).toList(growable: false);
  }

  @override
  List<Bookmark>? readCachedFirstPage() {
    final cached = _repo.readFirstPage(type);
    return cached == null ? null : _withoutPending(cached);
  }

  @override
  void onFirstPageLoaded(List<Bookmark> items) => unawaited(_repo.writeFirstPage(type, items));

  @override
  Future<PageResult<Bookmark, BookmarkCursor>> fetchPage(BookmarkCursor? cursor) async {
    final page = await _repo.page(type, cursor);
    return PageResult(_withoutPending(page.items), page.nextCursor);
  }

  @override
  Object idOf(Bookmark item) => item.key;

  /// Optimistically removes [b]; returns its former index (for undo) and
  /// whether the deletion already reached the server.
  Future<({int index, bool synced})> remove(Bookmark b) async {
    final index = state.items.indexWhere((e) => e.key == b.key);
    removeWhere((e) => e.key == b.key);
    unawaited(_repo.writeFirstPage(type, state.items));
    try {
      final synced = await _repo.remove(b);
      return (index: index, synced: synced);
    } on Object {
      if (ref.mounted) _insertAt(b, index);
      rethrow;
    }
  }

  /// Undo for [remove].
  Future<bool> restore(Bookmark b, int index) async {
    _insertAt(b, index);
    try {
      return await _repo.restore(b);
    } on Object {
      if (ref.mounted) removeWhere((e) => e.key == b.key);
      rethrow;
    }
  }

  void _insertAt(Bookmark b, int index) {
    if (state.items.any((e) => e.key == b.key)) return;
    final items = [...state.items];
    items.insert(index < 0 ? 0 : index.clamp(0, items.length), b);
    state = state.copyWith(items: items);
    unawaited(_repo.writeFirstPage(type, items));
  }
}

final bookmarksProvider = NotifierProvider.autoDispose
    .family<BookmarksNotifier, PagedState<Bookmark, BookmarkCursor>, BookmarkType>(BookmarksNotifier.new);
