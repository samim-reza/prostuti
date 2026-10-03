import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/app_image.dart';
import 'package:prostuti/features/profile/data/profile.dart';

/// Person row used by friends, requests, suggestions and search.
class UserTile extends StatelessWidget {
  const UserTile({
    required this.user,
    this.subtitle,
    this.extra,
    this.trailing,
    this.bottom,
    this.avatarRadius = 24,
    super.key,
  });

  final UserSummary user;

  /// Second line (e.g. "@username · district").
  final String? subtitle;

  /// Optional widget under the subtitle (chips, mutual friends…).
  final Widget? extra;
  final Widget? trailing;

  /// Optional full-width row under the tile (action buttons).
  final Widget? bottom;
  final double avatarRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return InkWell(
      onTap: () => unawaited(context.push(Routes.userProfile(user.id))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.sm + 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                UserAvatar(name: user.displayName, url: user.avatarUrl, radius: avatarRadius),
                Gap.w12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Text(subtitle!, style: muted, maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (extra != null) ...[Gap.h4, extra!],
                    ],
                  ),
                ),
                if (trailing != null) ...[Gap.w8, trailing!],
              ],
            ),
            if (bottom != null) ...[
              Gap.h8,
              Padding(
                padding: EdgeInsets.only(left: avatarRadius * 2 + Gap.md),
                child: bottom,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "@username · district".
String userSubtitle(UserSummary user, {String? district}) =>
    ['@${user.username}', if (district != null && district.trim().isNotEmpty) district.trim()].join(' · ');
