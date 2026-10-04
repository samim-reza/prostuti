import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/cache/cached_fetcher.dart';
import 'package:prostuti/core/config/app_constants.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/network/rpc.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/offline/offline_queue.dart';
import 'package:prostuti/core/utils/json.dart';
import 'package:prostuti/features/feed/data/comment.dart';
import 'package:prostuti/features/feed/data/offline_ops.dart';
import 'package:prostuti/features/feed/data/post.dart';
import 'package:prostuti/features/feed/data/report.dart';
import 'package:prostuti/features/feed/l10n/social_failures.dart';
import 'package:prostuti/features/profile/data/profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Posts, reactions, comments and reports — offline-first.
///
/// * Reads: every list is keyset-paginated on the server. The first page of
///   the feed, of each profile's posts and of each post's comments, plus
///   post details, go through [CachedFetcher] (persisted), so they paint
///   instantly on a cold start and keep rendering offline.
/// * Writes: text posts, comments, reactions and comment likes use
///   client-generated ids and fall back to the [OfflineQueue] when offline;
///   replays are idempotent (duplicate ids are ignored, `react_to_post` sets
///   an absolute state, comment likes converge to the desired state).
class FeedRepository {
  FeedRepository(this._client, this._cache);

  final SupabaseClient _client;
  final CachedFetcher _cache;

  static const pageSize = AppConstants.pageSize;
  static const commentPageSize = 20;
  static const uuid = Uuid();

  /// Fresh for a few minutes (always revalidated by the lists anyway); stale
  /// copies keep serving offline.
  static const listPolicy = CachePolicy(ttl: Duration(minutes: 5), negativeTtl: Duration(minutes: 1));
  static const postPolicy = CachePolicy(ttl: Duration(minutes: 2), negativeTtl: Duration(minutes: 1));

  /// Older snapshots are not shown at all.
  static const snapshotMaxAge = Duration(days: 7);

  final _synced = StreamController<SocialSync>.broadcast();

  /// Writes delivered by the outbox after having been queued offline.
  Stream<SocialSync> get synced => _synced.stream;

  String? get currentUserId => _client.auth.currentUser?.id;

  String _requireUid() => currentUserId ?? (throw const AuthFailure('not_authenticated'));

  String get _scope => currentUserId ?? 'anon';

  String _feedKey(String? authorId) => authorId == null ? 'feed:first:$_scope' : 'feed:author:$_scope:$authorId';
  String _postKey(String id) => 'feed:post:$_scope:$id';
  String _commentsKey(String postId) => 'feed:comments:$_scope:$postId';

  // ---------------------------------------------------------------------------
  // Feed
  // ---------------------------------------------------------------------------

  /// A page of the feed (or of one author's posts). The first page is
  /// fetched through the cache: online it always revalidates, offline the
  /// saved copy is returned.
  Future<List<Post>> fetchFeed({Keyset? before, String? authorId, int limit = pageSize}) {
    Future<List<Post>> network() async {
      final rows = await _client.rpcList(
        'get_feed',
        params: {
          'p_limit': limit,
          if (before != null) 'p_before_created': before.createdAtIso,
          if (before != null) 'p_before_id': before.id,
          'p_author': ?authorId,
        },
      );
      return rows.map(Post.fromJson).toList(growable: false);
    }

    if (before != null) return network();
    return _cache.get<List<Post>>(
      _feedKey(authorId),
      forceRefresh: true,
      fetch: network,
      encode: _encodePosts,
      decode: _decodePosts,
      policy: listPolicy,
      isEmpty: (list) => list.isEmpty,
    );
  }

  /// Synchronous read of the saved first page (memory LRU → Hive) for an
  /// instant first paint.
  List<Post>? readCachedFirstPage({String? authorId}) {
    if (currentUserId == null) return null;
    final entry = _cache.store.read(_feedKey(authorId));
    if (entry == null || entry.negative || entry.data is! List) return null;
    if (DateTime.now().difference(entry.storedAt) > snapshotMaxAge) return null;
    try {
      return _decodePosts(entry.data);
    } on Object {
      return null;
    }
  }

  /// Saves the current head of a list (after local changes such as a new
  /// post or reaction), so the offline snapshot matches what the user saw.
  Future<void> cacheFirstPage(List<Post> posts, {String? authorId}) async {
    if (currentUserId == null) return;
    final head = posts.where((p) => !p.pendingSync).take(pageSize).toList(growable: false);
    await _cache.store.write(_feedKey(authorId), _encodePosts(head), listPolicy.ttl);
  }

  static Object? _encodePosts(List<Post> posts) => [for (final p in posts) p.toJson()];

  static List<Post> _decodePosts(Object? json) => [
    for (final e in (json as List? ?? const []).whereType<Map<dynamic, dynamic>>())
      Post.fromJson(Map<String, dynamic>.from(e)),
  ];

  /// A single post (`get_feed` with `p_post`); `null` when it doesn't exist
  /// or isn't visible to me. Cached so it opens offline.
  Future<Post?> fetchPost(String id, {bool force = false}) => _cache.get<Post?>(
    _postKey(id),
    forceRefresh: force,
    fetch: () async {
      final rows = await _client.rpcList('get_feed', params: {'p_post': id, 'p_limit': 1});
      return rows.isEmpty ? null : Post.fromJson(rows.first);
    },
    encode: (p) => p?.toJson(),
    decode: (j) => j is Map ? Post.fromJson(Map<String, dynamic>.from(j)) : null,
    policy: postPolicy,
    isEmpty: (p) => p == null,
  );

  /// Keeps the cached copy of an opened post in line with local changes.
  Future<void> cachePost(Post post) async {
    if (post.pendingSync || currentUserId == null) return;
    await _cache.store.write(_postKey(post.id), post.toJson(), postPolicy.ttl);
  }

  // ---------------------------------------------------------------------------
  // Create / edit / delete
  // ---------------------------------------------------------------------------

  /// Publishes a text-only post. Works offline: the post gets a client id and
  /// is queued; the returned copy then has `pendingSync = true`.
  Future<Post> createTextPost({
    required UserSummary author,
    required String body,
    required PostVisibility visibility,
  }) async {
    final uid = _requireUid();
    final id = uuid.v4();
    final payload = <String, dynamic>{
      'id': id,
      'author_id': uid,
      'body': body.trim(),
      'visibility': visibility.wire,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'author': author.toJson(),
    };
    final post = await runOrQueue<Post>(SocialOps.createPost, payload, id: id, direct: () => _insertPost(payload));
    return post ?? _pendingPost(payload);
  }

  /// Uploads [images] (already WebP-compressed) in parallel, then inserts the
  /// post and selects it back. Uploaded files are removed again if the insert
  /// fails, so no orphaned media is left behind. Needs the network.
  Future<Post> createPostWithImages({
    required UserSummary author,
    required String body,
    required List<Uint8List> images,
    required PostVisibility visibility,
    void Function(int done, int total)? onProgress,
  }) async {
    final uid = _requireUid();
    final urls = await _uploadImages(uid, images, onProgress);
    try {
      final row = await guard(
        () => _client
            .from('posts')
            .insert({
              'id': uuid.v4(),
              'author_id': uid,
              'body': body.trim().isEmpty ? null : body.trim(),
              'image_paths': urls,
              'visibility': visibility.wire,
            })
            .select(Post.columns)
            .single(),
      );
      return Post.fromRow(row, author);
    } on Object {
      unawaited(_removeByUrls(urls));
      rethrow;
    }
  }

  /// Idempotent insert used both directly and by the outbox: a replay whose
  /// first attempt already succeeded hits the primary key and is treated as
  /// success.
  Future<Post> _insertPost(Map<String, dynamic> payload) async {
    final author = UserSummary.fromJson(Map<String, dynamic>.from(payload['author'] as Map));
    try {
      final row = await guard(
        () => _client
            .from('posts')
            .insert({
              'id': payload['id'],
              'author_id': payload['author_id'],
              'body': payload['body'],
              'visibility': payload['visibility'],
            })
            .select(Post.columns)
            .single(),
      );
      return Post.fromRow(row, author);
    } on ConflictFailure {
      return await fetchPost(payload['id'] as String, force: true) ??
          _pendingPost(payload).copyWith(pendingSync: false);
    }
  }

  Post _pendingPost(Map<String, dynamic> p) => Post(
    id: p.str('id'),
    author: UserSummary.fromJson(p.obj('author')),
    body: p.strOrNull('body'),
    visibility: PostVisibility.parse(p['visibility']),
    createdAt: p.dateOr('created_at', DateTime.now()),
    pendingSync: true,
  );

  /// My posts still waiting in the outbox, newest first.
  List<Post> pendingPosts() => [
    for (final p in pendingPayloads(SocialOps.createPost).reversed)
      if (p['author_id'] == currentUserId) _pendingPost(p),
  ];

  /// Updates an own post. [keptUrls] are existing images to keep (in order);
  /// [newImages] are uploaded and appended. Removed images are deleted from
  /// storage after the row is saved. Needs the network.
  Future<Post> updatePost({
    required Post original,
    required String body,
    required List<String> keptUrls,
    required List<Uint8List> newImages,
    required PostVisibility visibility,
    void Function(int done, int total)? onProgress,
  }) async {
    final uid = _requireUid();
    final uploaded = await _uploadImages(uid, newImages, onProgress);
    try {
      final row = await guard(
        () => _client
            .from('posts')
            .update({
              'body': body.trim().isEmpty ? null : body.trim(),
              'image_paths': [...keptUrls, ...uploaded],
              'visibility': visibility.wire,
              'edited_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', original.id)
            .select(Post.columns)
            .single(),
      );
      final removed = original.imageUrls.where((u) => !keptUrls.contains(u)).toList();
      if (removed.isNotEmpty) unawaited(_removeByUrls(removed));
      return Post.fromRow(row, original.author).copyWith(
        reactionSummary: original.reactionSummary,
        myReaction: original.myReaction,
        clearMyReaction: original.myReaction == null,
      );
    } on Object {
      unawaited(_removeByUrls(uploaded));
      rethrow;
    }
  }

  Future<void> deletePost(Post post) async {
    await guard(() => _client.from('posts').delete().eq('id', post.id));
    unawaited(_cache.invalidate(_postKey(post.id)));
    if (post.imageUrls.isNotEmpty) unawaited(_removeByUrls(post.imageUrls));
  }

  Future<List<String>> _uploadImages(String uid, List<Uint8List> images, void Function(int, int)? onProgress) async {
    if (images.isEmpty) return const [];
    final bucket = _client.storage.from(AppConstants.postMediaBucket);
    var done = 0;
    onProgress?.call(0, images.length);
    final uploadedPaths = <String>[];
    try {
      return await Future.wait([
        for (final bytes in images)
          () async {
            final type = sniffImageType(bytes);
            final path = '$uid/${uuid.v4()}.${type.extension}';
            await guard(
              () => bucket.uploadBinary(
                path,
                bytes,
                fileOptions: FileOptions(contentType: type.mime, cacheControl: '31536000'),
              ),
            );
            uploadedPaths.add(path);
            onProgress?.call(++done, images.length);
            return bucket.getPublicUrl(path);
          }(),
      ]);
    } on Object {
      if (uploadedPaths.isNotEmpty) unawaited(_removePaths(uploadedPaths));
      rethrow;
    }
  }

  Future<void> _removeByUrls(List<String> urls) {
    final uid = currentUserId;
    final paths = [
      for (final u in urls)
        if (storagePathFromPublicUrl(u, AppConstants.postMediaBucket) case final p?)
          if (uid != null && p.startsWith('$uid/')) p,
    ];
    return _removePaths(paths);
  }

  Future<void> _removePaths(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await _client.storage.from(AppConstants.postMediaBucket).remove(paths);
    } on Object {
      // Best effort: an orphaned image is harmless.
    }
  }

  // ---------------------------------------------------------------------------
  // Reactions
  // ---------------------------------------------------------------------------

  /// Sets, changes or (with `null`) removes my reaction.
  Future<ReactionResult> react(String postId, ReactionType? type) async {
    final json = await _client.rpcMap('react_to_post', params: {'p_post': postId, 'p_type': type?.wire});
    return ReactionResult.fromJson(json);
  }

  /// [react] when possible, otherwise queued (`null` result). Safe to replay:
  /// `react_to_post` stores an absolute state.
  Future<ReactionResult?> reactOrQueue(String postId, ReactionType? type) {
    final payload = {'post_id': postId, 'type': type?.wire};
    return runOrQueue(SocialOps.react, payload, id: uuid.v4(), direct: () => react(postId, type));
  }

  /// Reactions still waiting in the outbox, oldest first.
  List<(String, ReactionType?)> pendingReactions() => [
    for (final p in pendingPayloads(SocialOps.react)) (p.str('post_id'), ReactionType.tryParse(p['type'])),
  ];

  // ---------------------------------------------------------------------------
  // Comments
  // ---------------------------------------------------------------------------

  /// Oldest first. Top-level comments when [parentId] is null, otherwise the
  /// replies of that comment. The first top-level page is cached.
  Future<List<Comment>> fetchComments(String postId, {String? parentId, Keyset? after, int limit = commentPageSize}) {
    Future<List<Comment>> network() async {
      final rows = await _client.rpcList(
        'get_comments',
        params: {
          'p_post': postId,
          'p_parent': ?parentId,
          'p_limit': limit,
          if (after != null) 'p_after_created': after.createdAtIso,
          if (after != null) 'p_after_id': after.id,
        },
      );
      return rows.map(Comment.fromJson).toList(growable: false);
    }

    if (parentId != null || after != null) return network();
    return _cache.get<List<Comment>>(
      _commentsKey(postId),
      forceRefresh: true,
      fetch: network,
      encode: (list) => [for (final c in list) c.toJson()],
      decode: _decodeComments,
      policy: listPolicy,
      isEmpty: (list) => list.isEmpty,
    );
  }

  List<Comment>? readCachedComments(String postId) {
    if (currentUserId == null) return null;
    final entry = _cache.store.read(_commentsKey(postId));
    if (entry == null || entry.negative || entry.data is! List) return null;
    if (DateTime.now().difference(entry.storedAt) > snapshotMaxAge) return null;
    try {
      return _decodeComments(entry.data);
    } on Object {
      return null;
    }
  }

  Future<void> cacheComments(String postId, List<Comment> comments) async {
    if (currentUserId == null) return;
    final head = comments.where((c) => !c.pendingSync).take(commentPageSize);
    await _cache.store.write(_commentsKey(postId), [for (final c in head) c.toJson()], listPolicy.ttl);
  }

  static List<Comment> _decodeComments(Object? json) => [
    for (final e in (json as List? ?? const []).whereType<Map<dynamic, dynamic>>())
      Comment.fromJson(Map<String, dynamic>.from(e)),
  ];

  /// Adds a comment or reply with a client id. Works offline: the returned
  /// comment then has `pendingSync = true`.
  Future<Comment> addComment({
    required String postId,
    required String body,
    required UserSummary author,
    String? parentId,
  }) async {
    final uid = _requireUid();
    final id = uuid.v4();
    final payload = <String, dynamic>{
      'id': id,
      'post_id': postId,
      'author_id': uid,
      'parent_id': parentId,
      'body': body.trim(),
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'author': author.toJson(),
    };
    final comment = await runOrQueue<Comment>(
      SocialOps.addComment,
      payload,
      id: id,
      direct: () => _insertComment(payload),
    );
    return comment ?? _pendingComment(payload);
  }

  Future<Comment> _insertComment(Map<String, dynamic> payload) async {
    final author = UserSummary.fromJson(payload.obj('author'));
    try {
      final row = await guard(
        () => _client
            .from('comments')
            .insert({
              'id': payload['id'],
              'post_id': payload['post_id'],
              'author_id': payload['author_id'],
              'parent_id': payload['parent_id'],
              'body': payload['body'],
            })
            .select(Comment.columns)
            .single(),
      );
      return Comment.fromRow(row, author);
    } on ConflictFailure {
      // Replay of an insert that already went through.
      return _pendingComment(payload).copyWith(pendingSync: false);
    }
  }

  Comment _pendingComment(Map<String, dynamic> p) => Comment(
    id: p.str('id'),
    postId: p.str('post_id'),
    parentId: p.strOrNull('parent_id'),
    author: UserSummary.fromJson(p.obj('author')),
    body: p.str('body'),
    createdAt: p.dateOr('created_at', DateTime.now()),
    pendingSync: true,
  );

  /// Queued comments of a post (top-level when [parentId] is null), oldest first.
  List<Comment> pendingComments(String postId, {String? parentId}) => [
    for (final p in pendingPayloads(SocialOps.addComment))
      if (p['post_id'] == postId && p['parent_id'] == parentId) _pendingComment(p),
  ];

  Future<void> deleteComment(String id) => guard(() => _client.from('comments').delete().eq('id', id));

  /// Returns `(liked, likeCount)` after the toggle.
  Future<(bool, int)> toggleCommentLike(String commentId) async {
    final json = await _client.rpcMap('toggle_comment_like', params: {'p_comment': commentId});
    return (json['liked'] == true, (json['like_count'] as num?)?.toInt() ?? 0);
  }

  /// Drives a comment like to [liked] (the RPC is a toggle, so a replay that
  /// lands on the wrong side toggles once more — idempotent overall).
  Future<(bool, int)> _setCommentLike(String commentId, {required bool liked}) async {
    var result = await toggleCommentLike(commentId);
    if (result.$1 != liked) result = await toggleCommentLike(commentId);
    return result;
  }

  /// Likes/unlikes now, or queues the desired state (`null` result).
  Future<(bool, int)?> setCommentLikeOrQueue(String commentId, {required bool liked}) => runOrQueue(
    SocialOps.commentLike,
    {'comment_id': commentId, 'liked': liked},
    id: uuid.v4(),
    direct: () => _setCommentLike(commentId, liked: liked),
  );

  // ---------------------------------------------------------------------------
  // Outbox handlers
  // ---------------------------------------------------------------------------

  /// Registers the replay handlers with the [OfflineQueue] (idempotent).
  void registerOfflineHandlers() {
    OfflineQueue.instance
      ..register(SocialOps.createPost, (p) async => _synced.add(SyncedPost(await _insertPost(p))))
      ..register(SocialOps.addComment, (p) async => _synced.add(SyncedComment(await _insertComment(p))))
      ..register(SocialOps.react, (p) async {
        final postId = p.str('post_id');
        final result = await react(postId, ReactionType.tryParse(p['type']));
        // Only the last queued reaction for a post updates the UI (no flicker).
        final later = pendingPayloads(SocialOps.react).where((e) => e['post_id'] == postId).length > 1;
        if (!later) _synced.add(SyncedReaction(postId, result));
      })
      ..register(SocialOps.commentLike, (p) async {
        final id = p.str('comment_id');
        final (liked, count) = await _setCommentLike(id, liked: p.boolean('liked'));
        _synced.add(SyncedCommentLike(commentId: id, liked: liked, likeCount: count));
      });
  }

  // ---------------------------------------------------------------------------
  // Moderation & misc
  // ---------------------------------------------------------------------------

  Future<void> report({required ReportTarget target, required String targetId, required ReportReason reason}) {
    final uid = _requireUid();
    return guard(
      () => _client.from('reports').insert({
        'reporter_id': uid,
        'target_type': target.name,
        'target_id': targetId,
        'reason': reason.name,
      }),
    );
  }

  void dispose() => unawaited(_synced.close());
}

/// Detected image container → file extension + MIME type for the upload.
/// `MediaService` returns WebP, but falls back to the original bytes (JPEG,
/// PNG) when compression fails, so the content type is sniffed, not assumed.
({String extension, String mime}) sniffImageType(Uint8List bytes) {
  bool at(int offset, List<int> sig) {
    if (bytes.length < offset + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (bytes[offset + i] != sig[i]) return false;
    }
    return true;
  }

  if (at(0, const [0xFF, 0xD8, 0xFF])) return (extension: 'jpg', mime: 'image/jpeg');
  if (at(0, const [0x89, 0x50, 0x4E, 0x47])) return (extension: 'png', mime: 'image/png');
  return (extension: 'webp', mime: 'image/webp');
}

/// `https://…/storage/v1/object/public/<bucket>/<path>` → `<path>`.
String? storagePathFromPublicUrl(String url, String bucket) {
  final marker = '/object/public/$bucket/';
  final i = url.indexOf(marker);
  if (i < 0) return null;
  final path = url.substring(i + marker.length).split('?').first;
  return path.isEmpty ? null : Uri.decodeComponent(path);
}

final feedRepositoryProvider = Provider<FeedRepository>((ref) {
  registerFailureMessages(socialFailureResolver);
  final repo = FeedRepository(ref.watch(supabaseProvider), ref.watch(cachedFetcherProvider))..registerOfflineHandlers();
  ref.onDispose(repo.dispose);
  return repo;
});
