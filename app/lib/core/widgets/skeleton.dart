import 'package:flutter/material.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:shimmer/shimmer.dart';

/// Shimmering placeholder block.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({this.width, this.height = 14, this.radius = 8, super.key});
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Wraps children in a single shimmer (one animation for the whole list is
/// much cheaper than one per item).
class SkeletonShimmer extends StatelessWidget {
  const SkeletonShimmer({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Shimmer.fromColors(baseColor: scheme.surfaceContainerHighest, highlightColor: scheme.surface, child: child);
  }
}

/// Generic list skeleton used while the first page loads.
class SkeletonList extends StatelessWidget {
  const SkeletonList({this.itemCount = 6, this.itemHeight = 72, super.key});
  final int itemCount;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Gap.lg),
        itemCount: itemCount,
        separatorBuilder: (_, _) => Gap.h12,
        itemBuilder: (_, _) => Row(
          children: [
            const SkeletonBox(width: 44, height: 44, radius: 22),
            Gap.w12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonBox(width: 160),
                  Gap.h8,
                  SkeletonBox(height: itemHeight - 44 > 10 ? 10 : 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card-shaped skeleton (feed posts, notes).
class SkeletonCards extends StatelessWidget {
  const SkeletonCards({this.count = 3, this.height = 180, super.key});
  final int count;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        padding: const EdgeInsets.all(Gap.lg),
        itemCount: count,
        separatorBuilder: (_, _) => Gap.h16,
        itemBuilder: (_, _) => SkeletonBox(height: height, radius: 16),
      ),
    );
  }
}
