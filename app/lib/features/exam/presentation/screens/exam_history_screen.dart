import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/paged_list_view.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/exam/application/exam_failure_messages.dart';
import 'package:prostuti/features/exam/application/exam_providers.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/exam/presentation/utils/exam_kind_style.dart';
import 'package:prostuti/features/exam/presentation/utils/exam_title.dart';

/// Every submitted exam, newest first (keyset by `submitted_at`; the first
/// page is cached for instant/offline paint).
class ExamHistoryScreen extends ConsumerWidget {
  const ExamHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    registerExamFailureMessages();
    final l = context.l10n;
    final state = ref.watch(examHistoryProvider);
    final notifier = ref.read(examHistoryProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text(l.examHistoryTitle)),
      body: PagedListView<ExamHistoryItem>(
        state: state,
        onLoadMore: notifier.loadMore,
        onRefresh: notifier.refresh,
        onRetry: notifier.retry,
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xl),
        separator: Gap.h8,
        empty: EmptyView(
          icon: Icons.history_toggle_off_rounded,
          title: l.examHistoryEmpty,
          message: l.examHistoryEmptyBody,
          action: () => context.go(Routes.exams),
          actionLabel: l.examHistoryEmptyCta,
        ),
        itemBuilder: (context, item, _) => _HistoryTile(item: item),
      ),
    );
  }
}

class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({required this.item});
  final ExamHistoryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bangla = context.isBn;
    final color = scoreColor(item.percent);
    final accent = item.kind.accent;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(Routes.examResult(item.sessionId)),
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), borderRadius: Radii.button),
                child: Icon(item.kind.icon, color: accent),
              ),
              Gap.w12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      examTitleOf(context, ref, item.title, item.kind),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    Gap.h4,
                    Text(
                      '${item.kind.label(context)} · ${Fmt.date(item.submittedAt, bangla: bangla)}, '
                      '${Fmt.time(item.submittedAt, bangla: bangla)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Gap.w8,
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${Fmt.score(item.score, bangla: bangla)}/${Fmt.score(item.maxScore, bangla: bangla)}',
                    style: theme.textTheme.titleMedium?.copyWith(color: color),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: Gap.xxs),
                    padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 1),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: Radii.chip),
                    child: Text(
                      Fmt.percent(item.percent, bangla: bangla),
                      style: theme.textTheme.labelSmall?.copyWith(color: color),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
