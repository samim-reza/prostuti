import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/cache/cache_store.dart';
import 'package:prostuti/core/config/app_constants.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/network/rpc.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/offline/offline_queue.dart';
import 'package:prostuti/core/pagination/paged_state.dart';
import 'package:prostuti/core/utils/json.dart';
import 'package:prostuti/features/bookmarks/data/bookmark.dart';
import 'package:prostuti/features/feed/data/post.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BookmarksRepository {
  BookmarksRepository(this._client, this._store);

  final SupabaseClient _client;
  final CacheStore _store;

  /// Offline-queue operation types.
  static const removeOp = 'bookmarks.remove';
  static const restoreOp = 'bookmarks.restore';

  static const pageSize = AppConstants.pageSize;

  /// First pages stay on disk for a month so saved items render offline.
  static const _firstPageTtl = Duration(days: 30);

  String? get uid => _client.auth.currentUser?.id;

  String _uidOrThrow() => uid ?? (throw const AuthFailure('not_authenticated'));

  static String _cacheKey(String uid, BookmarkType type) => 'bookmarks:$uid:${type.name}';

  /// Keyset page ordered by `created_at desc, item_id desc` (served by the
  /// `(user_id, created_at desc)` index).
  Future<PageResult<Bookmark, BookmarkCursor>> page(BookmarkType type, BookmarkCursor? after) async {
    final userId = _uidOrThrow();
    final rows = await guard(() {
      var q = _client.from('bookmarks').select(Bookmark.columns).eq('user_id', userId).eq('item_type', type.name);
      if (after != null) q = q.or(after.orFilter);
      return q.order('created_at', ascending: false).order('item_id', ascending: false).limit(pageSize);
    });
    final items = rows.map(Bookmark.fromJson).toList(growable: false);
    final next = items.length < pageSize ? null : BookmarkCursor(items.last.createdAt, items.last.itemId);
    return PageResult(items, next);
  }

  List<Bookmark>? readFirstPage(BookmarkType type) {
    final userId = uid;
    if (userId == null) return null;
    final raw = _store.read(_cacheKey(userId, type))?.data;
    if (raw is! List) return null;
    return raw.whereType<Map<dynamic, dynamic>>().map((e) => Bookmark.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> writeFirstPage(BookmarkType type, List<Bookmark> items) async {
    final userId = uid;
    if (userId == null) return;
    await _store.write(_cacheKey(userId, type), items.take(pageSize).map((b) => b.toJson()).toList(), _firstPageTtl);
  }

  /// Removes now, or queues the removal while offline. Returns true if synced.
  Future<bool> remove(Bookmark b) =>
      OfflineQueue.instance.run(removeOp, {'item_type': b.type.name, 'item_id': b.itemId});

  /// Puts a removed bookmark back (undo) with its original timestamp so it
  /// returns to the same place in the list. Returns true if synced.
  Future<bool> restore(Bookmark b) => OfflineQueue.instance.run(restoreOp, b.toJson());

  /// Saves a community post with a `Post.toJson()` snapshot. The restore op
  /// is an upsert, so saving it again just moves it to the top. Returns true
  /// if synced.
  Future<bool> savePost(Post post) => restore(
    Bookmark(type: BookmarkType.post, itemId: post.id, payload: post.toJson(), createdAt: DateTime.now().toUtc()),
  );

  Future<void> _applyRemove(Map<String, dynamic> p) async {
    final userId = _uidOrThrow();
    await guard(
      () => _client
          .from('bookmarks')
          .delete()
          .eq('user_id', userId)
          .eq('item_type', p.str('item_type'))
          .eq('item_id', p.str('item_id')),
    );
  }

  Future<void> _applyRestore(Map<String, dynamic> p) async {
    final userId = _uidOrThrow();
    await guard(() => _client.from('bookmarks').upsert({'user_id': userId, ...p}));
  }

  /// Bookmark keys whose removal hasn't reached the server yet.
  static Set<String> pendingRemovals() => netPendingRemovals(
    [...OfflineQueue.instance.pendingOf(removeOp), ...OfflineQueue.instance.pendingOf(restoreOp)],
    removeOp: removeOp,
    restoreOp: restoreOp,
  );
}

final bookmarksRepositoryProvider = Provider<BookmarksRepository>((ref) {
  final repo = BookmarksRepository(ref.watch(supabaseProvider), ref.watch(cacheStoreProvider));
  OfflineQueue.instance
    ..register(BookmarksRepository.removeOp, repo._applyRemove)
    ..register(BookmarksRepository.restoreOp, repo._applyRestore);
  return repo;
});
