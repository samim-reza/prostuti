import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/entitlements/feature_access.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/study_plan/application/plan_providers.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/online_guard.dart';

/// User-facing message for a failed plan generation.
String planGenerationErrorMessage(BuildContext context, Object error) {
  final f = AppFailure.from(error);
  return switch (f) {
    NetworkFailure() || RateLimitFailure() => failureMessage(context, f),
    _ => context.l10n.studyPlanGenerateFailed,
  };
}

/// Runs plan generation and reports failures (add-on sheet when locked).
Future<bool> generatePlanWithFeedback(BuildContext context, WidgetRef ref) async {
  if (!ensureOnline(context)) return false;
  final ok = await ref.read(planGenerationProvider.notifier).generate();
  if (!context.mounted) return ok;
  if (ok) {
    showInfoSnack(context, context.l10n.studyPlanGenerated);
  } else {
    final error = ref.read(planGenerationProvider).error;
    if (error is FeatureLockedFailure) {
      showLockedSheet(context);
    } else {
      showInfoSnack(context, planGenerationErrorMessage(context, error ?? const UnknownFailure('')));
    }
  }
  return ok;
}

/// Refreshes plan data a little later (after a server-side re-plan job had
/// time to run). Uses the container, so it is safe after the widget is gone.
void refreshPlanDataLater(BuildContext context, {Duration delay = const Duration(seconds: 8)}) {
  final container = ProviderScope.containerOf(context, listen: false);
  unawaited(Future<void>.delayed(delay, () => refreshPlanData(container.read, quiet: true)));
}
