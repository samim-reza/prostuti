import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/features/study_plan/data/plan_models.dart';

/// Weak topics of a weak-topic exam day; tapping one opens practice for it.
class WeakTopicChips extends StatelessWidget {
  const WeakTopicChips({required this.topics, super.key});

  final List<WeakTopic> topics;

  @override
  Widget build(BuildContext context) {
    final bangla = context.isBn;
    return Wrap(
      spacing: Gap.sm,
      runSpacing: Gap.sm,
      children: [
        for (final t in topics)
          ActionChip(
            avatar: const Icon(Icons.trending_down_rounded, size: 18, color: AppColors.danger),
            label: Text(
              t.mastery == null
                  ? t.name(bangla: bangla)
                  : '${t.name(bangla: bangla)} · ${context.n((t.mastery! * 100).round())}%',
            ),
            tooltip: context.l10n.studyPlanPracticeTopic,
            onPressed: () => context.push(Routes.practice(topicId: t.topicId)),
          ),
      ],
    );
  }
}
