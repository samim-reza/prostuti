import 'package:flutter/material.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/pagination/paged_state.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/state_views.dart';

/// Admin tools act on live data only: returns false (and tells the user)
/// when there is no connection.
bool ensureOnline(BuildContext context) {
  if (ConnectivityService.instance.isOnline) return true;
  showInfoSnack(context, context.l10n.offlineUnavailable);
  return false;
}

/// Error state that explains "needs internet" for network failures.
class AdminErrorView extends StatelessWidget {
  const AdminErrorView({required this.error, required this.onRetry, super.key});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (AppFailure.from(error) is NetworkFailure) {
      return EmptyView(
        icon: Icons.cloud_off_rounded,
        title: l.offlineUnavailable,
        message: l.adminOfflineHint,
        action: onRetry,
        actionLabel: l.retry,
      );
    }
    return ErrorView(error: error, onRetry: onRetry);
  }
}

/// True when a paged list failed before showing anything because of the network.
bool isOfflineFirstPageError(PagedState<Object?, Object?> s) =>
    s.items.isEmpty && s.error != null && s.error is NetworkFailure;

/// Small rounded status label.
class AdminTag extends StatelessWidget {
  const AdminTag({required this.label, required this.color, this.icon, super.key});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.xxs),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: Radii.chip),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), Gap.w4],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Section heading used across admin screens.
class AdminSectionTitle extends StatelessWidget {
  const AdminSectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Gap.xl, bottom: Gap.sm),
      child: Text(text, style: theme.textTheme.titleMedium),
    );
  }
}
