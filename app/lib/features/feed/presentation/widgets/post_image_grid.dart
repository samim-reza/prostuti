import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/widgets/app_image.dart';
import 'package:prostuti/features/feed/presentation/screens/image_viewer_screen.dart';

/// 1–4 images laid out like a social feed: one wide image, two side by side,
/// one large + two stacked, or a 2×2 grid. Tapping opens the zoomable viewer.
class PostImageGrid extends StatelessWidget {
  const PostImageGrid({required this.urls, super.key});

  final List<String> urls;

  static const _gap = 2.0;

  void _open(BuildContext context, int index) {
    unawaited(ImageViewerScreen.open(context, urls: urls, initialIndex: index));
  }

  Widget _tile(BuildContext context, int index) {
    final l = context.l10n;
    return Semantics(
      button: true,
      label: '${l.feedViewPhoto}, ${l.feedPhotoOf(context.n(index + 1), context.n(urls.length))}',
      child: GestureDetector(
        onTap: () => _open(context, index),
        child: AppNetworkImage(url: urls[index]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    final count = urls.length.clamp(1, 4);
    Widget expanded(int i) => Expanded(child: _tile(context, i));
    final grid = switch (count) {
      1 => _tile(context, 0),
      2 => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          expanded(0),
          const SizedBox(width: _gap),
          expanded(1),
        ],
      ),
      3 => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 2, child: _tile(context, 0)),
          const SizedBox(width: _gap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                expanded(1),
                const SizedBox(height: _gap),
                expanded(2),
              ],
            ),
          ),
        ],
      ),
      _ => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                expanded(0),
                const SizedBox(width: _gap),
                expanded(1),
              ],
            ),
          ),
          const SizedBox(height: _gap),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                expanded(2),
                const SizedBox(width: _gap),
                expanded(3),
              ],
            ),
          ),
        ],
      ),
    };
    return AspectRatio(aspectRatio: count == 2 ? 2 : (count == 1 ? 4 / 3 : 1), child: grid);
  }
}
