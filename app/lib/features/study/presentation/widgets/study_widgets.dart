import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:prostuti/features/question_bank/application/offline_packs.dart';
import 'package:prostuti/features/question_bank/presentation/widgets/subject_widgets.dart';

/// Gradient call-to-action for today's current-affairs notes.
class NotesHeroCard extends StatelessWidget {
  const NotesHeroCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final on = scheme.onPrimary;
    return Semantics(
      button: true,
      label: l.studyHubNotesTitle,
      child: Material(
        borderRadius: Radii.card,
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [scheme.primary, Color.lerp(scheme.primary, Colors.black, 0.4)!],
            ),
          ),
          child: InkWell(
            onTap: () => context.push(Routes.notes),
            child: Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.studyHubNotesTitle, style: theme.textTheme.titleMedium?.copyWith(color: on)),
                        Gap.h4,
                        Text(
                          l.studyHubNotesBody,
                          style: theme.textTheme.bodySmall?.copyWith(color: on.withValues(alpha: 0.9)),
                        ),
                        Gap.h12,
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.xs + 2),
                          decoration: BoxDecoration(color: on.withValues(alpha: 0.18), borderRadius: Radii.chip),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(l.studyHubNotesCta, style: theme.textTheme.labelLarge?.copyWith(color: on)),
                              Gap.w4,
                              Icon(Icons.arrow_forward_rounded, size: 16, color: on),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Gap.w12,
                  Icon(Icons.newspaper_rounded, size: 56, color: on.withValues(alpha: 0.85)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sliver grid of subjects with mastery; tap → practice that subject.
class SubjectQuickGrid extends ConsumerWidget {
  const SubjectQuickGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjects = ref.watch(subjectsProvider);
    final list = subjects.value;
    if (list == null) {
      if (subjects.hasError) {
        return SliverToBoxAdapter(
          child: ErrorView(error: subjects.error!, compact: true, onRetry: () => ref.invalidate(subjectsProvider)),
        );
      }
      return const SliverToBoxAdapter(child: SkeletonCards(count: 2, height: 96));
    }
    // Cell height follows the user's font scale so Bangla titles never clip.
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return SliverGrid.builder(
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: Gap.md,
        crossAxisSpacing: Gap.md,
        mainAxisExtent: 92 + 56 * textScale,
      ),
      itemCount: list.length,
      itemBuilder: (context, i) => _SubjectTile(subject: list[i]),
    );
  }
}

class _SubjectTile extends ConsumerWidget {
  const _SubjectTile({required this.subject});
  final Subject subject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final offline = ref.watch(offlinePacksProvider.select((s) => s.packs.containsKey(subject.id)));
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(Routes.practice(subjectId: subject.id)),
        onLongPress: () => context.push(Routes.subjectDetail(subject.id)),
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SubjectBadge(icon: subject.iconData, color: subject.color, size: 38),
                  const Spacer(),
                  if (offline) Icon(Icons.offline_pin_rounded, size: 18, color: theme.colorScheme.primary),
                ],
              ),
              Gap.h8,
              Expanded(
                child: Text(
                  subject.name(context),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(height: 1.3),
                ),
              ),
              MasteryBar(mastery: subject.mastery),
            ],
          ),
        ),
      ),
    );
  }
}
