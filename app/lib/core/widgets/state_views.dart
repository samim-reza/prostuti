import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/skeleton.dart';

/// Friendly empty state with an optional action.
class EmptyView extends StatelessWidget {
  const EmptyView({
    this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
    this.actionLabel,
    this.compact = false,
    super.key,
  });

  final String? title;
  final String? message;
  final IconData icon;
  final VoidCallback? action;
  final String? actionLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? Gap.lg : Gap.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(Gap.lg),
              decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
              child: Icon(icon, size: compact ? 32 : 44, color: scheme.primary),
            ),
            Gap.h16,
            Text(
              title ?? context.l10n.emptyGeneric,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              Gap.h8,
              Text(
                message!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              Gap.h16,
              FilledButton.tonal(
                onPressed: action,
                style: FilledButton.styleFrom(minimumSize: const Size(160, 44)),
                child: Text(actionLabel ?? context.l10n.retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Error state that explains the failure and offers a retry.
class ErrorView extends StatelessWidget {
  const ErrorView({required this.error, this.onRetry, this.compact = false, super.key});

  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return EmptyView(
      icon: Icons.cloud_off_rounded,
      title: context.l10n.errorGeneric,
      message: failureMessage(context, error),
      action: onRetry,
      actionLabel: context.l10n.retry,
      compact: compact,
    );
  }
}

/// Renders an [AsyncValue] with consistent loading / error / data states.
/// Keeps showing previous data while refreshing (no flicker).
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    required this.value,
    required this.data,
    this.loading,
    this.onRetry,
    this.isEmpty,
    this.empty,
    super.key,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final Widget? loading;
  final VoidCallback? onRetry;
  final bool Function(T data)? isEmpty;
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      data: (d) => (isEmpty?.call(d) ?? false) ? (empty ?? const EmptyView()) : data(d),
      loading: () => loading ?? const SkeletonList(),
      error: (e, _) => ErrorView(error: e, onRetry: onRetry),
    );
  }
}

/// Shows a floating snack bar with a localized error message.
void showErrorSnack(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(failureMessage(context, error))));
}

void showInfoSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirmDialog(
  BuildContext context, {
  String? title,
  String? message,
  String? confirmLabel,
  bool destructive = false,
}) async {
  final l = context.l10n;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title ?? l.confirmDeleteTitle),
      content: Text(message ?? l.confirmDeleteBody),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel ?? l.ok),
        ),
      ],
    ),
  );
  return result ?? false;
}
