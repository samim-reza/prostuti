import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/config/app_constants.dart';
import 'package:prostuti/core/entitlements/feature_access.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:prostuti/features/exam/application/exam_failure_messages.dart';
import 'package:prostuti/features/exam/application/model_test_plan.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/exam/presentation/utils/exam_kind_style.dart';
import 'package:prostuti/features/exam/presentation/widgets/exam_launcher.dart';

/// Full BCS-pattern model tests: 25/50/100/200 marks, duration at the BCS
/// pace, subject distribution preview and the rules.
class ModelTestsScreen extends ConsumerStatefulWidget {
  const ModelTestsScreen({super.key});

  @override
  ConsumerState<ModelTestsScreen> createState() => _ModelTestsScreenState();
}

class _ModelTestsScreenState extends ConsumerState<ModelTestsScreen> {
  int _size = 100;

  @override
  Widget build(BuildContext context) {
    registerExamFailureMessages();
    final l = context.l10n;
    final theme = Theme.of(context);
    final subjects = ref.watch(subjectsProvider);
    final list = subjects.value ?? const <Subject>[];
    final hasFeature = ref.watch(hasFeatureProvider(Features.modelTest));
    final accessKnown = ref.watch(featureAccessProvider.select((a) => a.hasValue));
    final bangla = context.isBn;
    final negative = Fmt.score(AppConstants.defaultNegativeMark, bangla: bangla);

    return Scaffold(
      appBar: AppBar(title: Text(l.examModelTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xl),
        children: [
          Card(
            color: ExamKind.modelTest.accent.withValues(alpha: 0.1),
            child: Padding(
              padding: Gap.card,
              child: Row(
                children: [
                  Icon(Icons.assignment_rounded, size: 40, color: ExamKind.modelTest.accent),
                  Gap.w12,
                  Expanded(child: Text(l.examModelIntro, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
          ),
          Gap.h16,
          Text(l.examModelChooseSize, style: theme.textTheme.titleMedium),
          Gap.h8,
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            // Fixed height that grows with the font scale (an aspect ratio
            // would shrink the cards on narrow phones and clip Bangla text).
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: Gap.md,
              crossAxisSpacing: Gap.md,
              mainAxisExtent: 60 + 58 * MediaQuery.textScalerOf(context).scale(1),
            ),
            children: [
              for (final size in ModelTestPlan.sizes)
                _SizeCard(
                  size: size,
                  shares: ModelTestPlan.distribution(list, size),
                  selected: size == _size,
                  onTap: () => setState(() => _size = size),
                ),
            ],
          ),
          Gap.h16,
          Text(l.examModelDistribution, style: theme.textTheme.titleMedium),
          Gap.h8,
          if (subjects.isLoading && list.isEmpty)
            const SizedBox(height: 220, child: SkeletonList(itemCount: 3))
          else
            _Distribution(shares: ModelTestPlan.distribution(list, _size)),
          Gap.h16,
          Text(l.examModelRules, style: theme.textTheme.titleMedium),
          Gap.h8,
          Card(
            child: Padding(
              padding: Gap.card,
              child: Column(
                children: [
                  _Rule(icon: Icons.remove_circle_outline_rounded, text: l.examModelRuleNegative(negative)),
                  _Rule(icon: Icons.timer_outlined, text: l.examModelRuleTimer),
                  _Rule(icon: Icons.restore_rounded, text: l.examModelRuleResume),
                  if (accessKnown && !hasFeature)
                    _Rule(icon: Icons.workspace_premium_rounded, text: l.examModelRuleQuota),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.md),
          child: FilledButton.icon(
            onPressed: () => unawaited(ExamLauncher.start(context, ref, ExamKind.modelTest, config: {'size': _size})),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(l.examModelStart(context.n(_size))),
          ),
        ),
      ),
    );
  }
}

class _SizeCard extends StatelessWidget {
  const _SizeCard({required this.size, required this.shares, required this.selected, required this.onTap});

  final int size;
  final List<SubjectShare> shares;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = shares.isEmpty ? size : ModelTestPlan.totalQuestions(shares);
    final minutes = (ModelTestPlan.duration(size, shares: shares).inSeconds / 60).ceil();
    final fg = selected ? scheme.onPrimary : scheme.onSurface;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? scheme.primary : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.card,
          side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(l.examMarks(context.n(size)), style: theme.textTheme.titleLarge?.copyWith(color: fg)),
                Gap.h4,
                Text(
                  '${l.examQuestionsCount(context.n(count))} · ${Fmt.minutes(minutes, bangla: context.isBn)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: fg.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Distribution extends StatelessWidget {
  const _Distribution({required this.shares});
  final List<SubjectShare> shares;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final max = shares.fold<int>(1, (m, s) => s.count > m ? s.count : m);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
        child: Column(
          children: [
            for (final share in shares)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.xs + 1),
                child: Row(
                  children: [
                    Icon(share.subject.iconData, size: 18, color: share.subject.color),
                    Gap.w8,
                    Expanded(
                      flex: 5,
                      child: Text(
                        share.subject.name(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Gap.w8,
                    Expanded(
                      flex: 3,
                      child: ClipRRect(
                        borderRadius: Radii.chip,
                        child: LinearProgressIndicator(
                          value: share.count / max,
                          minHeight: 6,
                          color: share.subject.color,
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      child: Text(context.n(share.count), textAlign: TextAlign.end, style: theme.textTheme.labelLarge),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          Gap.w12,
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
