import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/entitlements/feature_access.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/exam/application/exam_failure_messages.dart';
import 'package:prostuti/features/exam/application/exam_providers.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';

/// Opens the AI explanation for [question] in a bottom sheet. Needs the
/// network; a locked feature closes the sheet and shows the add-on upsell.
Future<void> showAiExplainSheet(BuildContext context, Question question) async {
  if (!ConnectivityService.instance.isOnline) {
    showInfoSnack(context, context.l10n.offlineUnavailable);
    return;
  }
  final locked = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AiExplainSheet(question: question),
  );
  if ((locked ?? false) && context.mounted) showLockedSheet(context);
}

/// "এআই ব্যাখ্যা" text button used on question cards.
class AiExplainButton extends StatelessWidget {
  const AiExplainButton({required this.question, super.key});

  final Question question;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => unawaited(showAiExplainSheet(context, question)),
      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
      label: Text(context.l10n.examAiExplain),
      style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
    );
  }
}

class _AiExplainSheet extends ConsumerWidget {
  const _AiExplainSheet({required this.question});

  final Question question;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final key = (question.id, context.isBn ? 'bn' : 'en');
    final value = ref.watch(aiExplanationProvider(key));

    ref.listen(aiExplanationProvider(key), (_, next) {
      if (next.error is FeatureLockedFailure && Navigator.of(context).canPop()) Navigator.of(context).pop(true);
    });

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.xl),
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: AppColors.info),
              Gap.w8,
              Expanded(child: Text(l.examAiExplain, style: Theme.of(context).textTheme.titleMedium)),
            ],
          ),
          Gap.h8,
          Text(question.stem, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          Gap.h16,
          value.when(
            skipLoadingOnRefresh: false,
            loading: () => _Loading(label: l.examAiExplainLoading),
            error: (e, _) => _AiError(error: e, onRetry: () => ref.invalidate(aiExplanationProvider(key))),
            data: (ai) => _AiBody(ai: ai),
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            Gap.w8,
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
        Gap.h16,
        const SkeletonShimmer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [SkeletonBox(), Gap.h8, SkeletonBox(), Gap.h8, SkeletonBox(width: 220)],
          ),
        ),
      ],
    );
  }
}

class _AiBody extends StatelessWidget {
  const _AiBody({required this.ai});
  final AiExplanation ai;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(ai.explanation, style: Theme.of(context).textTheme.bodyLarge),
        if (ai.memoryTip != null) ...[
          Gap.h16,
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Gap.md),
            decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.12), borderRadius: Radii.button),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.tips_and_updates_rounded, color: AppColors.gold, size: 20),
                Gap.w8,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.examAiMemoryTip, style: Theme.of(context).textTheme.titleSmall),
                      Gap.h4,
                      Text(ai.memoryTip!, style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        Gap.h16,
        Text(
          l.examAiDisclaimer,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _AiError extends StatelessWidget {
  const _AiError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final failure = AppFailure.from(error);
    // A missing / failing Edge Function is "not available yet", not a crash.
    final unavailable = failure is NotFoundFailure || (failure is ServerFailure && failure.code != 'rate_limited');
    final message = unavailable ? context.l10n.examAiUnavailable : examErrorMessage(context, failure);
    return EmptyView(
      compact: true,
      icon: Icons.cloud_off_rounded,
      title: message,
      action: failure is FeatureLockedFailure ? null : onRetry,
      actionLabel: context.l10n.retry,
    );
  }
}
