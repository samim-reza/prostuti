import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/app_image.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';

/// "What's on your mind?" card at the top of the feed.
class ComposerPromptCard extends ConsumerWidget {
  const ComposerPromptCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = ref.watch(currentProfileProvider.select((p) => p.value?.displayName));
    final avatar = ref.watch(currentProfileProvider.select((p) => p.value?.avatarUrl));
    void compose() => unawaited(context.push(Routes.composePost));
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.xs),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: compose,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.sm, Gap.md),
            child: Row(
              children: [
                UserAvatar(name: name, url: avatar, radius: 21),
                Gap.w12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.feedComposePrompt, style: theme.textTheme.titleMedium),
                      Text(
                        l.feedComposePromptHint,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: compose,
                  tooltip: l.feedAddPhotos,
                  icon: Icon(Icons.add_photo_alternate_outlined, color: scheme.primary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Post-shaped shimmer used while the first page loads.
class PostSkeletonList extends StatelessWidget {
  const PostSkeletonList({this.count = 3, this.header, super.key});

  final int count;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      children: [
        ?header,
        SkeletonShimmer(
          child: Column(children: [for (var i = 0; i < count; i++) _PostSkeleton(withImage: i.isEven)]),
        ),
      ],
    );
  }
}

class _PostSkeleton extends StatelessWidget {
  const _PostSkeleton({required this.withImage});

  final bool withImage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.xs + 2),
      child: Card(
        child: Padding(
          padding: Gap.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  SkeletonBox(width: 42, height: 42, radius: 21),
                  Gap.w12,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [SkeletonBox(width: 140), Gap.h8, SkeletonBox(width: 80, height: 10)],
                  ),
                ],
              ),
              Gap.h16,
              const SkeletonBox(),
              Gap.h8,
              const SkeletonBox(width: 220),
              if (withImage) ...[Gap.h12, const SkeletonBox(height: 160, radius: 12)],
              Gap.h16,
              const Row(
                children: [
                  Expanded(child: SkeletonBox(height: 12)),
                  Gap.w16,
                  Expanded(child: SkeletonBox(height: 12)),
                  Gap.w16,
                  Expanded(child: SkeletonBox(height: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small numeric badge on an app-bar icon (hidden at zero, "99+" cap).
class CountBadgeIcon extends StatelessWidget {
  const CountBadgeIcon({required this.icon, required this.count, super.key});

  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      label: Text(count > 99 ? '${context.n(99)}+' : context.n(count)),
      child: Icon(icon),
    );
  }
}
