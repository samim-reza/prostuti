import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/features/study_plan/application/plan_providers.dart';
import 'package:prostuti/features/study_plan/application/topic_lookup.dart';
import 'package:prostuti/features/study_plan/data/plan_models.dart';
import 'package:prostuti/features/study_plan/presentation/widgets/plan_ui.dart';

/// One routine checklist row: tick-off circle, item icon, title, meta line
/// (subject · topic · minutes · question count) and an action button.
class PlanItemTile extends ConsumerWidget {
  const PlanItemTile({
    required this.dayId,
    required this.item,
    required this.canMarkDone,
    required this.onMarkDone,
    required this.onOpen,
    super.key,
  });

  final int dayId;
  final PlanItem item;

  /// False for future days (the server only accepts today/past days).
  final bool canMarkDone;
  final VoidCallback onMarkDone;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lookup = ref.watch(topicLookupProvider);
    final pending =
        item.done &&
        ref.watch(pendingPlanItemsProvider.select((s) => s.contains(PendingPlanItemsNotifier.keyOf(dayId, item.key))));
    final subject = lookup.subjectFor(subjectId: item.subjectId, topicId: item.topicId);
    final topic = lookup.topic(item.topicId);
    final accent = subject?.color ?? scheme.primary;
    final done = item.done;
    final title = item.title(bangla: context.isBn);

    final meta = <String>[
      if (subject != null) subject.name(context),
      if (topic != null) topic.name(context),
      if ((item.minutes ?? 0) > 0) PlanFmt.minutes(context, item.minutes!),
      if ((item.count ?? 0) > 0) l.studyPlanQuestionCount(item.count!, context.n(item.count!)),
    ];
    final enabled = canMarkDone && item.canComplete && !done;

    return InkWell(
      onTap: item.type == PlanItemType.rest ? null : onOpen,
      borderRadius: Radii.button,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.xs),
        child: Row(
          children: [
            _DoneToggle(done: done, enabled: enabled, onTap: onMarkDone, label: title),
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: Radii.button),
              child: Icon(item.type.icon, size: 20, color: accent),
            ),
            Gap.w12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.isEmpty ? l.studyPlanUntitledItem : title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      decoration: done ? TextDecoration.lineThrough : null,
                      color: done ? scheme.onSurfaceVariant : scheme.onSurface,
                    ),
                  ),
                  if (pending)
                    Row(
                      children: [
                        Icon(Icons.schedule_rounded, size: 14, color: scheme.onSurfaceVariant),
                        Gap.w4,
                        Flexible(
                          child: Text(
                            l.studyPlanPendingSync,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    )
                  else if (meta.isNotEmpty)
                    Text(
                      meta.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            if (item.type != PlanItemType.rest && !done) ...[
              Gap.w8,
              TextButton(
                onPressed: onOpen,
                style: TextButton.styleFrom(
                  minimumSize: const Size(56, 44),
                  padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                ),
                child: Text(item.type.actionLabel(context)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DoneToggle extends StatelessWidget {
  const _DoneToggle({required this.done, required this.enabled, required this.onTap, required this.label});

  final bool done;
  final bool enabled;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = context.l10n;
    return Semantics(
      checked: done,
      enabled: enabled,
      label: label,
      child: Tooltip(
        message: done ? l.studyPlanItemDone : l.studyPlanMarkDone,
        child: InkResponse(
          onTap: enabled ? onTap : null,
          radius: 24,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? AppColors.success : Colors.transparent,
                  border: Border.all(
                    color: done
                        ? AppColors.success
                        : (enabled ? scheme.outline : scheme.outlineVariant.withValues(alpha: 0.6)),
                    width: 2,
                  ),
                ),
                child: done ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
