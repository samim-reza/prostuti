import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/config/app_constants.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:prostuti/features/exam/application/exam_clock.dart';
import 'package:prostuti/features/exam/application/exam_failure_messages.dart';
import 'package:prostuti/features/exam/application/exam_providers.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/exam/data/exam_repository.dart';

/// Starts exams from anywhere in the app with consistent UX: offline check,
/// a blocking "preparing" dialog, double-tap protection and friendly errors
/// (add-on sheet for locked features, a quota dialog for free daily limits).
abstract final class ExamLauncher {
  static bool _busy = false;

  static Future<void> start(
    BuildContext context,
    WidgetRef ref,
    ExamKind kind, {
    Map<String, dynamic> config = const {},
    bool replace = false,
  }) async {
    if (_busy) return;
    final l = context.l10n;
    if (!ConnectivityService.instance.isOnline) {
      showInfoSnack(context, l.offlineUnavailable);
      return;
    }
    _busy = true;
    final repo = ref.read(examRepositoryProvider);
    final navigator = Navigator.of(context, rootNavigator: true);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _StartingDialog(label: l.examStarting),
      ),
    );
    try {
      final session = await repo.start(kind, config: config);
      navigator.pop();
      if (!context.mounted) return;
      ref.invalidate(activeExamProvider);
      final route = Routes.examSession(session.sessionId);
      if (replace) {
        context.pushReplacement(route);
      } else {
        unawaited(context.push(route));
      }
    } on Object catch (e) {
      navigator.pop();
      if (!context.mounted) return;
      final failure = AppFailure.from(e);
      if (failure is RateLimitFailure && (failure.action?.startsWith('quota:') ?? false)) {
        await showQuotaDialog(context);
      } else {
        showExamError(context, failure);
      }
    } finally {
      _busy = false;
    }
  }

  /// Free plan used its daily attempt: explain and offer the add-ons.
  static Future<void> showQuotaDialog(BuildContext context) async {
    final l = context.l10n;
    final upgrade = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.workspace_premium_rounded, color: AppColors.gold, size: 36),
        title: Text(l.examQuotaTitle, textAlign: TextAlign.center),
        content: Text(l.examQuotaBody, textAlign: TextAlign.center),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.examQuotaLater)),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.lockedCta),
          ),
        ],
      ),
    );
    if ((upgrade ?? false) && context.mounted) unawaited(context.push(Routes.addons));
  }
}

class _StartingDialog extends StatelessWidget {
  const _StartingDialog({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        child: Padding(
          padding: const EdgeInsets.all(Gap.xl),
          child: Row(
            children: [
              const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 3)),
              Gap.w16,
              Expanded(child: Text(label, style: Theme.of(context).textTheme.titleSmall)),
            ],
          ),
        ),
      ),
    );
  }
}

/// User's choice in [showExamSetupSheet].
@immutable
class ExamSetupChoice {
  const ExamSetupChoice({required this.count, this.subjectId});
  final int count;
  final int? subjectId;
}

const examCountOptions = [10, 20, 30, 50];

/// Bottom sheet to pick a subject (when [subjects] is given) and the number
/// of questions, with the resulting duration.
Future<ExamSetupChoice?> showExamSetupSheet(
  BuildContext context, {
  required String title,
  List<Subject>? subjects,
  int? initialSubjectId,
  int initialCount = 20,
}) {
  return showModalBottomSheet<ExamSetupChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ExamSetupSheet(
      title: title,
      subjects: subjects,
      initialSubjectId: initialSubjectId,
      initialCount: initialCount,
    ),
  );
}

class _ExamSetupSheet extends StatefulWidget {
  const _ExamSetupSheet({required this.title, required this.initialCount, this.subjects, this.initialSubjectId});

  final String title;
  final List<Subject>? subjects;
  final int? initialSubjectId;
  final int initialCount;

  @override
  State<_ExamSetupSheet> createState() => _ExamSetupSheetState();
}

class _ExamSetupSheetState extends State<_ExamSetupSheet> {
  late int? _subjectId = widget.initialSubjectId ?? widget.subjects?.firstOrNull?.id;
  late int _count = widget.initialCount;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final subjects = widget.subjects;
    final duration = ExamTiming.forQuestions(_count);
    final canStart = subjects == null || _subjectId != null;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
            child: Text(widget.title, style: theme.textTheme.titleLarge),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(Gap.lg),
              children: [
                if (subjects != null) ...[
                  Text(l.examSetupSubject, style: theme.textTheme.titleSmall),
                  Gap.h8,
                  Wrap(
                    spacing: Gap.sm,
                    runSpacing: Gap.sm,
                    children: [
                      for (final s in subjects)
                        ChoiceChip(
                          avatar: Icon(s.iconData, size: 18, color: s.color),
                          label: Text(s.name(context)),
                          selected: _subjectId == s.id,
                          onSelected: (_) => setState(() => _subjectId = s.id),
                        ),
                    ],
                  ),
                  Gap.h24,
                ],
                Text(l.examSetupCount, style: theme.textTheme.titleSmall),
                Gap.h8,
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [for (final c in examCountOptions) ButtonSegment(value: c, label: Text(context.n(c)))],
                  selected: {_count},
                  onSelectionChanged: (v) => setState(() => _count = v.first),
                ),
                Gap.h16,
                _InfoLine(
                  icon: Icons.timer_outlined,
                  text: l.examSetupSummary(
                    context.n(_count),
                    Fmt.minutes((duration.inSeconds / 60).ceil(), bangla: context.isBn),
                  ),
                ),
                Gap.h8,
                _InfoLine(
                  icon: Icons.remove_circle_outline_rounded,
                  text: l.examSetupNegative(Fmt.score(AppConstants.defaultNegativeMark, bangla: context.isBn)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.lg),
            child: FilledButton.icon(
              onPressed: canStart
                  ? () => Navigator.pop(context, ExamSetupChoice(count: _count, subjectId: _subjectId))
                  : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(l.examSetupStart),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.onSurfaceVariant),
        Gap.w8,
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}
