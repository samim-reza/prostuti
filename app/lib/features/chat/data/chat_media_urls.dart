import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/cache/lru_cache.dart';
import 'package:prostuti/core/config/app_constants.dart';
import 'package:prostuti/core/network/rpc.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef SignUrls = Future<Map<String, String>> Function(List<String> paths, int expiresInSeconds);

@immutable
class _SignedUrl {
  const _SignedUrl(this.url, this.expiresAt);
  final String url;
  final DateTime expiresAt;
}

/// Signed URLs for the private `chat-media` bucket.
///
/// * in-memory LRU keyed by object path, honouring each URL's expiry
///   (renewed 5 minutes early so an image never 403s mid-download);
/// * single-flight per path — many bubbles of the same image share one call;
/// * [prefetch] signs a whole page of images in ONE request
///   (`createSignedUrls`) instead of one round-trip per bubble.
class ChatMediaUrls {
  ChatMediaUrls(this._sign, {DateTime Function()? clock, int capacity = 300})
    : _now = clock ?? DateTime.now,
      _cache = LruCache<String, _SignedUrl>(capacity);

  factory ChatMediaUrls.supabase(SupabaseClient client) => ChatMediaUrls((paths, expiresIn) async {
    final bucket = client.storage.from(AppConstants.chatMediaBucket);
    if (paths.length == 1) {
      final url = await guard(() => bucket.createSignedUrl(paths.first, expiresIn));
      return {paths.first: url};
    }
    final results = await guard(() => bucket.createSignedUrlsResult(paths, expiresIn));
    return {
      for (final r in results)
        if (r is SignedUrlSuccess) r.path: r.signedUrl,
    };
  });

  static const lifetime = Duration(hours: 1);
  static const _renewEarly = Duration(minutes: 5);

  final SignUrls _sign;
  final DateTime Function() _now;
  final LruCache<String, _SignedUrl> _cache;
  final _inFlight = <String, Future<String>>{};

  /// A still-valid cached URL, or null (synchronous: lets bubbles that were
  /// prefetched render on the very first frame).
  String? peek(String path) {
    final hit = _cache.get(path);
    if (hit == null) return null;
    if (_now().isAfter(hit.expiresAt.subtract(_renewEarly))) {
      _cache.remove(path);
      return null;
    }
    return hit.url;
  }

  Future<String> get(String path) {
    final cached = peek(path);
    if (cached != null) return Future.value(cached);
    final pending = _inFlight[path];
    if (pending != null) return pending;
    final future = _signMany([path]).then((m) {
      final url = m[path];
      if (url == null) throw StateError('could not sign $path');
      return url;
    });
    _inFlight[path] = future;
    return future.whenComplete(() => _inFlight.remove(path));
  }

  /// Signs every path that is not cached (or in flight) with one request.
  Future<void> prefetch(Iterable<String> paths) async {
    final missing = paths.where((p) => peek(p) == null && !_inFlight.containsKey(p)).toSet().toList();
    if (missing.isEmpty) return;
    final batch = _signMany(missing);
    for (final p in missing) {
      // ignore() marks errors handled; whoever awaits it through [get] still
      // receives them.
      _inFlight[p] = batch.then((m) => m[p] ?? (throw StateError('could not sign $p')))..ignore();
    }
    try {
      await batch;
    } on Object {
      // Individual bubbles retry through [get].
    } finally {
      missing.forEach(_inFlight.remove);
    }
  }

  Future<Map<String, String>> _signMany(List<String> paths) async {
    final requestedAt = _now();
    final urls = await _sign(paths, lifetime.inSeconds);
    final expiresAt = requestedAt.add(lifetime);
    urls.forEach((path, url) => _cache.put(path, _SignedUrl(url, expiresAt)));
    return urls;
  }
}

/// Kept alive for the session so URLs survive leaving and re-opening chats.
final chatMediaUrlsProvider = Provider<ChatMediaUrls>((ref) => ChatMediaUrls.supabase(ref.watch(supabaseProvider)));
