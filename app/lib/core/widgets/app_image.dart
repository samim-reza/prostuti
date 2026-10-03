import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Network image with disk caching and *decode-size capping*: images are
/// decoded at the size they are displayed (× device pixel ratio) instead of
/// their full resolution, which keeps memory low on budget phones.
class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    super.key,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final scheme = Theme.of(context).colorScheme;
    Widget image = LayoutBuilder(
      builder: (context, constraints) {
        final w = width ?? (constraints.maxWidth.isFinite ? constraints.maxWidth : null);
        return CachedNetworkImage(
          imageUrl: url,
          width: width,
          height: height,
          fit: fit,
          memCacheWidth: w == null ? null : (w * dpr).round(),
          fadeInDuration: const Duration(milliseconds: 150),
          placeholder: (_, _) => ColoredBox(color: scheme.surfaceContainerHighest),
          errorWidget: (_, _, _) => ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant),
          ),
        );
      },
    );
    if (borderRadius != null) image = ClipRRect(borderRadius: borderRadius!, child: image);
    return image;
  }
}

/// Circular avatar with initials fallback.
class UserAvatar extends StatelessWidget {
  const UserAvatar({required this.name, this.url, this.radius = 20, super.key});

  final String? url;
  final String? name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initials = _initials(name);
    final size = radius * 2;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return CircleAvatar(
      radius: radius,
      backgroundColor: _colorFor(name ?? '', scheme),
      foregroundImage: (url == null || url!.isEmpty)
          ? null
          : CachedNetworkImageProvider(url!, maxWidth: (size * dpr).round(), maxHeight: (size * dpr).round()),
      child: Text(
        initials,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: radius * 0.75),
      ),
    );
  }

  static String _initials(String? name) {
    final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts.first.characters.first;
    final second = parts.length > 1 ? parts[1].characters.first : '';
    return (first + second).toUpperCase();
  }

  static Color _colorFor(String seed, ColorScheme scheme) {
    const palette = [
      Color(0xFF0E7C66),
      Color(0xFF3559E0),
      Color(0xFF7A4BD6),
      Color(0xFFD9480F),
      Color(0xFFC2255C),
      Color(0xFF1F8FB3),
      Color(0xFF2E8B57),
      Color(0xFF5C7CFA),
    ];
    if (seed.isEmpty) return scheme.primary;
    return palette[seed.codeUnits.fold<int>(0, (a, b) => a + b) % palette.length];
  }
}
