import 'package:flutter/material.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/feed/data/report.dart';
import 'package:prostuti/features/feed/l10n/social_failures.dart';
import 'package:prostuti/features/feed/presentation/widgets/post_labels.dart';

/// Asks why the user reports something. Resolves to the chosen reason.
Future<ReportReason?> showReportSheet(BuildContext context) => showModalBottomSheet<ReportReason>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => const _ReportSheet(),
);

/// Full report flow: reason picker → [submit] → thank-you / error snack.
/// Reporting the same thing twice is answered gently, not as an error.
Future<void> reportFlow(BuildContext context, Future<void> Function(ReportReason reason) submit) async {
  if (!ensureOnline(context)) return;
  final reason = await showReportSheet(context);
  if (reason == null || !context.mounted) return;
  try {
    await submit(reason);
    if (context.mounted) showInfoSnack(context, context.l10n.feedReportThanks);
  } on Object catch (e) {
    if (!context.mounted) return;
    if (AppFailure.from(e) is ConflictFailure) {
      showInfoSnack(context, context.l10n.feedReportDuplicate);
    } else {
      showSocialError(context, e);
    }
  }
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet();

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  ReportReason? _reason;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.feedReportTitle, style: theme.textTheme.titleLarge),
            Gap.h4,
            Text(
              l.feedReportSubtitle,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            Gap.h12,
            RadioGroup<ReportReason>(
              groupValue: _reason,
              onChanged: (v) => setState(() => _reason = v),
              child: Column(
                children: [
                  for (final r in ReportReason.values)
                    RadioListTile<ReportReason>(
                      value: r,
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(r.icon),
                      title: Text(r.label(l)),
                    ),
                ],
              ),
            ),
            Gap.h12,
            FilledButton(
              onPressed: _reason == null ? null : () => Navigator.of(context).pop(_reason),
              child: Text(l.feedReportSubmit),
            ),
          ],
        ),
      ),
    );
  }
}
