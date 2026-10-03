import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/entitlements/feature_access.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/exam/data/exam_repository.dart';
import 'package:prostuti/features/study_plan/application/plan_exam.dart';
import 'package:prostuti/features/study_plan/application/plan_providers.dart';
import 'package:prostuti/features/study_plan/data/plan_models.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/online_guard.dart';

bool _starting = false;

/// Starts an exam for the plan and opens the exam screen. Shows a small
/// blocking progress dialog while the server picks questions; handles
/// `feature_locked` with the add-on sheet. Re-entrant taps are ignored.
Future<void> startPlanExam(BuildContext context, PlanExamLaunch launch) async {
  if (_starting || !ensureOnline(context)) return;
  _starting = true;
  final navigator = Navigator.of(context, rootNavigator: true);
  final container = ProviderScope.containerOf(context, listen: false);
  var dialogOpen = true;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _StartingExamDialog(),
    ).whenComplete(() => dialogOpen = false),
  );
  try {
    final session = await container.read(examRepositoryProvider).start(launch.kind, config: launch.config);
    if (dialogOpen) navigator.pop();
    if (!context.mounted) return;
    _starting = false;
    await context.push(Routes.examSession(session.sessionId));
    // Submitting the exam ticks the plan item off server-side.
    await refreshPlanData(container.read, quiet: true);
  } on Object catch (e) {
    if (dialogOpen) navigator.pop();
    if (!context.mounted) return;
    if (AppFailure.from(e) is FeatureLockedFailure) {
      showLockedSheet(context);
    } else {
      showErrorSnack(context, e);
    }
  } finally {
    _starting = false;
  }
}

/// Opens what a routine item asks for: practice/reading screens for study
/// items, an exam for exam items (only on unlocked days).
Future<void> openPlanItem(
  BuildContext context, {
  required int dayId,
  required PlanDayKind dayKind,
  required PlanItem item,
  required bool unlocked,
}) async {
  switch (item.type) {
    case PlanItemType.rest:
      return;
    case PlanItemType.exam:
      if (!unlocked) {
        showInfoSnack(context, context.l10n.studyPlanExamNotYet);
        return;
      }
      await startPlanExam(context, planExamLaunch(dayId: dayId, dayKind: dayKind, item: item));
    case PlanItemType.read || PlanItemType.practice || PlanItemType.revise || PlanItemType.other:
      await context.push(practiceRouteFor(item));
  }
}

class _StartingExamDialog extends StatelessWidget {
  const _StartingExamDialog();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        child: Padding(
          padding: const EdgeInsets.all(Gap.xl),
          child: Row(
            children: [
              const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
              Gap.w16,
              Expanded(child: Text(context.l10n.studyPlanStartingExam)),
            ],
          ),
        ),
      ),
    );
  }
}
