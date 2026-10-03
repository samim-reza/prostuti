import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_view/photo_view.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/features/chat/data/chat_media_urls.dart';

/// Stable disk-cache key for a private chat image: signed URLs change every
/// hour, the object path doesn't — so a re-signed URL still hits the cache.
String chatMediaCacheKey(String path) => 'chat-media/$path';

/// Used when no signed URL can be obtained (offline): the image still
/// renders if it is in the disk cache under [chatMediaCacheKey].
String _offlineUrl(String path) => 'https://offline.invalid/chat-media/$path';

/// A private `chat-media` image: local bytes while uploading, then a
/// signed URL (memory LRU) with disk caching keyed by the object path.
class ChatImage extends ConsumerStatefulWidget {
  const ChatImage({required this.path, this.localBytes, this.width = 240, this.height = 240, super.key});

  final String? path;
  final Uint8List? localBytes;
  final double width;
  final double height;

  @override
  ConsumerState<ChatImage> createState() => _ChatImageState();
}

class _ChatImageState extends ConsumerState<ChatImage> {
  Future<String>? _url;
  String? _ready;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(ChatImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _resolve();
  }

  void _resolve() {
    final path = widget.path;
    if (path == null || widget.localBytes != null) return;
    final urls = ref.read(chatMediaUrlsProvider);
    _ready = urls.peek(path);
    _url = _ready == null ? urls.get(path) : null;
  }

  void _retry() => setState(_resolve);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (widget.width * dpr).round();
    final placeholder = ColoredBox(color: scheme.surfaceContainerHighest);

    Widget child;
    final bytes = widget.localBytes;
    if (bytes != null) {
      child = Image.memory(bytes, fit: BoxFit.cover, cacheWidth: cacheWidth, gaplessPlayback: true);
    } else if (_ready != null) {
      child = _network(_ready!, cacheWidth, placeholder);
    } else {
      child = FutureBuilder<String>(
        future: _url,
        builder: (context, snap) {
          if (snap.hasError) return _network(_offlineUrl(widget.path!), cacheWidth, placeholder);
          if (!snap.hasData) return placeholder;
          return _network(snap.data!, cacheWidth, placeholder);
        },
      );
    }
    return SizedBox(width: widget.width, height: widget.height, child: child);
  }

  Widget _network(String url, int cacheWidth, Widget placeholder) => CachedNetworkImage(
    imageUrl: url,
    cacheKey: chatMediaCacheKey(widget.path!),
    fit: BoxFit.cover,
    memCacheWidth: cacheWidth,
    fadeInDuration: const Duration(milliseconds: 150),
    placeholder: (_, _) => placeholder,
    errorWidget: (context, _, _) => _broken(context),
  );

  Widget _broken(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: InkWell(
        onTap: _retry,
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: scheme.onSurfaceVariant,
            semanticLabel: context.l10n.chatImageLoadFailed,
          ),
        ),
      ),
    );
  }
}

/// Full-screen, zoomable viewer for a chat image.
class ChatImageViewer extends ConsumerWidget {
  const ChatImageViewer({required this.path, this.localBytes, super.key});

  final String? path;
  final Uint8List? localBytes;

  static Future<void> open(BuildContext context, {String? path, Uint8List? localBytes}) => Navigator.of(context)
      .push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ChatImageViewer(path: path, localBytes: localBytes),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = localBytes;
    final p = path;
    Widget body;
    if (bytes != null) {
      body = PhotoView(imageProvider: MemoryImage(bytes), minScale: PhotoViewComputedScale.contained);
    } else if (p != null) {
      body = FutureBuilder<String>(
        future: ref.read(chatMediaUrlsProvider).get(p),
        builder: (context, snap) {
          if (!snap.hasData && !snap.hasError) return const Center(child: CircularProgressIndicator());
          return PhotoView(
            imageProvider: CachedNetworkImageProvider(snap.data ?? _offlineUrl(p), cacheKey: chatMediaCacheKey(p)),
            minScale: PhotoViewComputedScale.contained,
            errorBuilder: (_, _, _) =>
                const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white70, size: 48)),
          );
        },
      );
    } else {
      body = const SizedBox.shrink();
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(context.l10n.chatPhoto)),
      body: body,
    );
  }
}
