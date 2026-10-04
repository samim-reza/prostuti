import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:prostuti/core/l10n/l10n.dart';

/// Full-screen, swipeable, pinch-to-zoom photo viewer. A photo viewer is dark
/// by convention in both themes, so it uses a fixed black canvas.
class ImageViewerScreen extends StatefulWidget {
  const ImageViewerScreen({required this.urls, this.initialIndex = 0, super.key});

  final List<String> urls;
  final int initialIndex;

  /// Pushed on the root navigator so it covers the bottom bar.
  static Future<void> open(BuildContext context, {required List<String> urls, int initialIndex = 0}) =>
      Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder<void>(
          opaque: false,
          barrierColor: Colors.black,
          pageBuilder: (_, _, _) => ImageViewerScreen(urls: urls, initialIndex: initialIndex),
          transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
        ),
      );

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late final PageController _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final multi = widget.urls.length > 1;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black54,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: multi
            ? Text(
                '${context.n(_index + 1)} / ${context.n(widget.urls.length)}',
                style: const TextStyle(color: Colors.white),
              )
            : null,
      ),
      body: PhotoViewGallery.builder(
        pageController: _controller,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _index = i),
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        loadingBuilder: (_, _) =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white70)),
        builder: (context, i) => PhotoViewGalleryPageOptions(
          imageProvider: CachedNetworkImageProvider(widget.urls[i]),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3,
          initialScale: PhotoViewComputedScale.contained,
          semanticLabel: l.feedPhotoOf(context.n(i + 1), context.n(widget.urls.length)),
          errorBuilder: (_, _, _) =>
              const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48)),
        ),
      ),
    );
  }
}
