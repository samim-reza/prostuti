import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/paged_list_view.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/admin/application/admin_controllers.dart';
import 'package:prostuti/features/admin/data/admin_models.dart';
import 'package:prostuti/features/admin/presentation/widgets/admin_common.dart';

/// Moderation queue: open / actioned / dismissed reports.
class AdminReportsScreen extends ConsumerStatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  ConsumerState<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends ConsumerState<AdminReportsScreen> {
  static const _statuses = ['open', 'actioned', 'dismissed'];
  String _status = 'open';

  Future<void> _resolve(AdminReportsNotifier notifier, AdminReport r, String action) async {
    final l = context.l10n;
    if (!ensureOnline(context)) return;
    if (action == 'hide') {
      final ok = await confirmDialog(
        context,
        title: _hideLabel(l, r.targetType),
        message: r.targetType == 'user' ? l.adminBanBody : l.adminHideBody,
        confirmLabel: _hideLabel(l, r.targetType),
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    try {
      await notifier.resolve(r, action);
      if (mounted) {
        showInfoSnack(context, switch (action) {
          'hide' => l.adminReportHidden,
          'restore' => l.adminReportRestored,
          _ => l.adminReportDismissed,
        });
      }
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final state = ref.watch(adminReportsProvider(_status));
    final notifier = ref.read(adminReportsProvider(_status).notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.adminReportsTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.sm),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [for (final s in _statuses) ButtonSegment(value: s, label: Text(_statusLabel(l, s)))],
                selected: {_status},
                onSelectionChanged: (s) => setState(() => _status = s.first),
              ),
            ),
          ),
        ),
      ),
      body: isOfflineFirstPageError(state)
          ? AdminErrorView(error: state.error!, onRetry: () => unawaited(notifier.refresh()))
          : PagedListView<AdminReport>(
              state: state,
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.lg),
              separator: Gap.h12,
              loading: const SkeletonCards(),
              onLoadMore: () => unawaited(notifier.loadMore()),
              onRefresh: notifier.refresh,
              onRetry: () => unawaited(notifier.retry()),
              empty: EmptyView(
                icon: Icons.verified_user_outlined,
                title: _status == 'open' ? l.adminReportsEmptyOpen : l.adminReportsEmpty,
              ),
              itemBuilder: (context, r, _) =>
                  _ReportCard(report: r, onResolve: (action) => unawaited(_resolve(notifier, r, action))),
            ),
    );
  }

  static String _statusLabel(AppLocalizations l, String s) => switch (s) {
    'open' => l.adminReportsOpen,
    'actioned' => l.adminReportsActioned,
    _ => l.adminReportsDismissed,
  };
}

String _hideLabel(AppLocalizations l, String targetType) => switch (targetType) {
  'user' => l.adminBanUser,
  'question' => l.adminReject,
  _ => l.adminHide,
};

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report, required this.onResolve});

  final AdminReport report;
  final ValueChanged<String> onResolve;

  (IconData, String) _target(AppLocalizations l) => switch (report.targetType) {
    'post' => (Icons.dynamic_feed_outlined, l.adminTargetPost),
    'comment' => (Icons.mode_comment_outlined, l.adminTargetComment),
    'user' => (Icons.person_outline_rounded, l.adminTargetUser),
    'message' => (Icons.chat_bubble_outline_rounded, l.adminTargetMessage),
    'question' => (Icons.quiz_outlined, l.adminTargetQuestion),
    _ => (Icons.help_outline_rounded, report.targetType),
  };

  String _reason(AppLocalizations l) => switch (report.reason) {
    'spam' => l.adminReasonSpam,
    'abuse' => l.adminReasonAbuse,
    'nudity' => l.adminReasonNudity,
    'violence' => l.adminReasonViolence,
    'misinformation' => l.adminReasonMisinformation,
    'wrong_answer' => l.adminReasonWrongAnswer,
    _ => l.adminReasonOther,
  };

  String? get _route => switch (report.targetType) {
    'post' => Routes.postDetail(report.targetId),
    'user' => Routes.userProfile(report.targetId),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, targetLabel) = _target(l);
    final route = _route;
    final preview = report.preview?.trim();

    return Card(
      child: Padding(
        padding: Gap.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: scheme.primary),
                Gap.w8,
                Expanded(
                  child: Wrap(
                    spacing: Gap.sm,
                    runSpacing: Gap.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(targetLabel, style: theme.textTheme.titleSmall),
                      AdminTag(label: _reason(l), color: AppColors.danger),
                    ],
                  ),
                ),
                Gap.w8,
                Text(
                  Fmt.timeAgo(report.createdAt, bangla: context.isBn),
                  style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            if (report.reporterName != null) ...[
              Gap.h4,
              Text(
                l.adminReportedBy(report.reporterName!),
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (report.details?.trim().isNotEmpty ?? false) ...[
              Gap.h8,
              Text('“${report.details!.trim()}”', style: theme.textTheme.bodyMedium),
            ],
            Gap.h8,
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Gap.md),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: Radii.button,
              ),
              child: Text(
                (preview == null || preview.isEmpty) ? l.adminPreviewUnavailable : preview,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: (preview == null || preview.isEmpty) ? FontStyle.italic : null,
                ),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Gap.h8,
            Wrap(
              spacing: Gap.xs,
              children: [
                if (route != null)
                  TextButton.icon(
                    onPressed: () => unawaited(context.push(route)),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text(l.adminViewTarget),
                  ),
                if (report.status == 'open') ...[
                  TextButton.icon(
                    onPressed: () => onResolve('dismiss'),
                    icon: const Icon(Icons.close_rounded),
                    label: Text(l.adminDismiss),
                  ),
                  TextButton.icon(
                    onPressed: () => onResolve('hide'),
                    style: TextButton.styleFrom(foregroundColor: scheme.error),
                    icon: const Icon(Icons.visibility_off_outlined),
                    label: Text(_hideLabel(l, report.targetType)),
                  ),
                ],
                if (report.status == 'actioned' && report.canRestore)
                  TextButton.icon(
                    onPressed: () => onResolve('restore'),
                    icon: const Icon(Icons.restore_rounded),
                    label: Text(l.adminRestore),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
