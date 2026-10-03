import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/bd_time.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/admin/application/admin_controllers.dart';
import 'package:prostuti/features/admin/data/admin_models.dart';
import 'package:prostuti/features/admin/presentation/widgets/admin_common.dart';
import 'package:prostuti/features/admin/presentation/widgets/schedule_editor_page.dart';
import 'package:prostuti/features/profile/application/profile_edit.dart';
import 'package:url_launcher/url_launcher.dart';

/// Exam dates (BPSC & co.). Changing a date re-plans every learner targeting
/// that exam — the database trigger does it and notifies them.
class AdminSchedulesScreen extends ConsumerStatefulWidget {
  const AdminSchedulesScreen({super.key});

  @override
  ConsumerState<AdminSchedulesScreen> createState() => _AdminSchedulesScreenState();
}

class _AdminSchedulesScreenState extends ConsumerState<AdminSchedulesScreen> {
  bool _saving = false;

  Future<void> _edit([AdminSchedule? initial]) async {
    final l = context.l10n;
    if (!ensureOnline(context)) return;
    final edited = await ScheduleEditorPage.open(context, initial: initial);
    if (edited == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(adminSchedulesProvider.notifier).save(edited);
      if (!mounted) return;
      final replanned = initial != null && !edited.sameDateAs(initial);
      showInfoSnack(context, replanned ? l.adminScheduleSavedReplan : l.adminScheduleSaved);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(adminSchedulesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.adminSchedulesTitle),
        bottom: _saving
            ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator())
            : null,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : () => unawaited(_edit()),
        icon: const Icon(Icons.add_rounded),
        label: Text(l.adminScheduleNew),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(adminSchedulesProvider.notifier).refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, 96),
          children: [
            const _ReplanBanner(),
            Gap.h16,
            ...async.when(
              skipLoadingOnRefresh: true,
              skipLoadingOnReload: true,
              loading: () => [const SkeletonCards(height: 140)],
              error: (e, _) => [AdminErrorView(error: e, onRetry: () => ref.invalidate(adminSchedulesProvider))],
              data: (list) => list.isEmpty
                  ? [EmptyView(icon: Icons.event_busy_outlined, title: l.adminSchedulesEmpty)]
                  : [
                      for (final s in list) ...[
                        _ScheduleCard(schedule: s, onEdit: _saving ? null : () => unawaited(_edit(s))),
                        Gap.h12,
                      ],
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplanBanner extends StatelessWidget {
  const _ReplanBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const color = AppColors.warning;
    return Container(
      padding: Gap.card,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: Radii.card,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: color),
          Gap.w12,
          Expanded(child: Text(context.l10n.adminScheduleReplanNotice, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _ScheduleCard extends ConsumerWidget {
  const _ScheduleCard({required this.schedule, required this.onEdit});

  final AdminSchedule schedule;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bangla = context.isBn;
    final s = schedule;
    final types = ref.watch(examTypesProvider).value ?? const <ExamTypeInfo>[];
    final typeName = types.where((t) => t.code == s.examType).map((t) => t.name(bangla: bangla)).firstOrNull;
    final days = DateTime.utc(
      s.expectedDate.year,
      s.expectedDate.month,
      s.expectedDate.day,
    ).difference(BdTime.today()).inDays;

    return Opacity(
      opacity: s.isActive ? 1 : 0.6,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.sm, Gap.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(bangla ? s.titleBn : s.titleEn, style: theme.textTheme.titleSmall),
                    Gap.h4,
                    Wrap(
                      spacing: Gap.sm,
                      runSpacing: Gap.xs,
                      children: [
                        AdminTag(label: typeName ?? s.examType, color: scheme.primary),
                        AdminTag(
                          label: s.isConfirmed ? l.adminScheduleConfirmedTag : l.adminScheduleTentativeTag,
                          color: s.isConfirmed ? AppColors.success : AppColors.warning,
                          icon: s.isConfirmed ? Icons.verified_rounded : Icons.schedule_rounded,
                        ),
                        if (!s.isActive) AdminTag(label: l.adminScheduleInactiveTag, color: scheme.outline),
                      ],
                    ),
                    Gap.h8,
                    Row(
                      children: [
                        Icon(Icons.event_rounded, size: 16, color: scheme.onSurfaceVariant),
                        Gap.w4,
                        Flexible(
                          child: Text(
                            '${Fmt.date(s.expectedDate, bangla: bangla)} · '
                            '${days >= 0 ? l.adminScheduleDaysLeft(context.n(days)) : l.adminSchedulePassed}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    if (s.notes?.trim().isNotEmpty ?? false) ...[
                      Gap.h4,
                      Text(s.notes!.trim(), style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                    if (s.sourceUrl != null) ...[
                      Gap.h4,
                      InkWell(
                        onTap: () => unawaited(_open(s.sourceUrl!)),
                        child: Text(
                          s.sourceUrl!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.primary),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(tooltip: l.adminScheduleEdit, onPressed: onEdit, icon: const Icon(Icons.edit_outlined)),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      // No browser available.
    }
  }
}
