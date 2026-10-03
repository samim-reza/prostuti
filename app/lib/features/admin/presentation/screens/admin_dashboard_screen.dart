import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/admin/application/admin_controllers.dart';
import 'package:prostuti/features/admin/data/admin_models.dart';
import 'package:prostuti/features/admin/data/admin_repository.dart';
import 'package:prostuti/features/admin/presentation/widgets/admin_common.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  final _running = <PipelineStage>{};

  Future<void> _run(PipelineStage stage, String title) async {
    final l = context.l10n;
    if (_running.contains(stage) || !ensureOnline(context)) return;
    final ok = await confirmDialog(
      context,
      title: l.adminPipelineConfirmTitle(title),
      message: l.adminPipelineConfirmBody,
      confirmLabel: l.adminPipelineRun,
    );
    if (!ok || !mounted) return;
    setState(() => _running.add(stage));
    try {
      final requestId = await ref.read(adminRepositoryProvider).runPipeline(stage);
      if (!mounted) return;
      showInfoSnack(
        context,
        requestId == null ? l.adminPipelineNotConfigured : l.adminPipelineStarted(title, context.n(requestId)),
      );
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _running.remove(stage));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final stats = ref.watch(adminDashboardProvider);
    final isAdmin = ref.watch(currentProfileProvider.select((p) => p.value?.isAdmin ?? false));
    final s = stats.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.adminTitle),
        actions: [
          IconButton(
            tooltip: l.adminRefresh,
            onPressed: () => ref.invalidate(adminDashboardProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(adminDashboardProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.xxl),
          children: [
            AdminSectionTitle(l.adminTodayOverview),
            stats.when(
              skipLoadingOnRefresh: true,
              skipLoadingOnReload: true,
              loading: () => const SkeletonShimmer(child: _StatGridSkeleton()),
              error: (e, _) => AdminErrorView(error: e, onRetry: () => ref.invalidate(adminDashboardProvider)),
              data: (d) => _StatGrid(stats: d),
            ),
            AdminSectionTitle(l.adminManage),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _NavTile(
                    icon: Icons.fact_check_outlined,
                    title: l.adminQuestionsTitle,
                    subtitle: l.adminQuestionsHint,
                    badge: s?.questionsUnverified,
                    route: Routes.adminQuestions,
                  ),
                  const Divider(indent: 56),
                  _NavTile(
                    icon: Icons.flag_outlined,
                    title: l.adminReportsTitle,
                    subtitle: l.adminReportsHint,
                    badge: s?.openReports,
                    route: Routes.adminReports,
                  ),
                  if (isAdmin) ...[
                    const Divider(indent: 56),
                    _NavTile(
                      icon: Icons.event_note_outlined,
                      title: l.adminSchedulesTitle,
                      subtitle: l.adminSchedulesHint,
                      route: Routes.adminSchedules,
                    ),
                  ],
                ],
              ),
            ),
            if (isAdmin) ...[
              AdminSectionTitle(l.adminPipelineTitle),
              Text(
                l.adminPipelineIntro,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              Gap.h8,
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (i, stage) in PipelineStage.values.indexed) ...[
                      if (i > 0) const Divider(indent: 56),
                      _PipelineTile(
                        stage: stage,
                        running: _running.contains(stage),
                        onRun: (title) => unawaited(_run(stage, title)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats});
  final AdminStats stats;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final bangla = context.isBn;
    String c(int v) => Fmt.count(v, bangla: bangla);
    final cards = <_StatCard>[
      _StatCard(icon: Icons.people_alt_outlined, label: l.adminStatUsers, value: c(stats.users), color: scheme.primary),
      _StatCard(
        icon: Icons.bolt_rounded,
        label: l.adminStatActiveToday,
        value: c(stats.activeToday),
        color: AppColors.success,
      ),
      _StatCard(
        icon: Icons.dynamic_feed_outlined,
        label: l.adminStatPostsToday,
        value: c(stats.postsToday),
        color: AppColors.info,
      ),
      _StatCard(
        icon: Icons.quiz_outlined,
        label: l.adminStatQuestions,
        value: c(stats.questions),
        color: scheme.primary,
      ),
      _StatCard(
        icon: Icons.pending_actions_outlined,
        label: l.adminStatUnverified,
        value: c(stats.questionsUnverified),
        color: AppColors.warning,
        route: Routes.adminQuestions,
      ),
      _StatCard(
        icon: Icons.outlined_flag_rounded,
        label: l.adminStatFlagged,
        value: c(stats.questionsFlagged),
        color: AppColors.danger,
        route: Routes.adminQuestions,
      ),
      _StatCard(
        icon: Icons.lightbulb_outline_rounded,
        label: l.adminStatFacts,
        value: c(stats.facts),
        color: AppColors.gold,
      ),
      _StatCard(
        icon: Icons.article_outlined,
        label: l.adminStatNotesToday,
        value: c(stats.notesToday),
        color: stats.notesToday == 0 ? AppColors.danger : AppColors.success,
      ),
      _StatCard(
        icon: stats.dailyExamToday ? Icons.task_alt_rounded : Icons.hourglass_empty_rounded,
        label: l.adminStatDailyExam,
        value: stats.dailyExamToday ? l.adminDailyExamReady : l.adminDailyExamMissing,
        color: stats.dailyExamToday ? AppColors.success : AppColors.danger,
      ),
      _StatCard(
        icon: Icons.event_available_outlined,
        label: l.adminStatActivePlans,
        value: c(stats.activePlans),
        color: AppColors.info,
      ),
      _StatCard(
        icon: Icons.report_outlined,
        label: l.adminStatOpenReports,
        value: c(stats.openReports),
        color: stats.openReports > 0 ? AppColors.danger : AppColors.success,
        route: Routes.adminReports,
      ),
      _StatCard(
        icon: Icons.auto_awesome_outlined,
        label: l.adminStatAiCalls,
        value: c(stats.aiCallsToday),
        footnote: l.adminStatCacheHits(c(stats.aiCacheHitsToday), Fmt.percent(stats.cacheHitPercent, bangla: bangla)),
        color: const Color(0xFF7A4BD6),
      ),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 76 + 36 * MediaQuery.textScalerOf(context).scale(1),
        crossAxisSpacing: Gap.md,
        mainAxisSpacing: Gap.md,
      ),
      itemBuilder: (_, i) => cards[i],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.footnote,
    this.route,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String? footnote;
  final String? route;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tint = scheme.brightness == Brightness.dark ? Color.lerp(color, Colors.white, 0.25) ?? color : color;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: route == null ? null : () => unawaited(context.push(route!)),
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: tint),
                  const Spacer(),
                  if (route != null) Icon(Icons.chevron_right_rounded, size: 18, color: scheme.onSurfaceVariant),
                ],
              ),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: theme.textTheme.titleLarge?.copyWith(color: tint)),
              ),
              Text(
                footnote == null ? label : '$label · $footnote',
                style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatGridSkeleton extends StatelessWidget {
  const _StatGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 8,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 76 + 36 * MediaQuery.textScalerOf(context).scale(1),
        crossAxisSpacing: Gap.md,
        mainAxisSpacing: Gap.md,
      ),
      itemBuilder: (_, _) => const SkeletonBox(height: 112, radius: 16),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.icon, required this.title, required this.subtitle, required this.route, this.badge});

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = badge ?? 0;
    return ListTile(
      leading: Icon(icon, color: scheme.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (count > 0) Badge(label: Text(Fmt.count(count, bangla: context.isBn))),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
      onTap: () => unawaited(context.push(route)),
    );
  }
}

class _PipelineTile extends StatelessWidget {
  const _PipelineTile({required this.stage, required this.running, required this.onRun});

  final PipelineStage stage;
  final bool running;
  final ValueChanged<String> onRun;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final (icon, title, hint) = switch (stage) {
      PipelineStage.ingestNews => (Icons.rss_feed_rounded, l.adminStageIngest, l.adminStageIngestHint),
      PipelineStage.dailyNotes => (Icons.article_outlined, l.adminStageNotes, l.adminStageNotesHint),
      PipelineStage.dailyExam => (Icons.quiz_outlined, l.adminStageExam, l.adminStageExamHint),
      PipelineStage.notifications => (Icons.campaign_outlined, l.adminStageNotify, l.adminStageNotifyHint),
    };
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: Text(hint),
      trailing: running
          ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
          : IconButton.filledTonal(
              tooltip: l.adminPipelineRun,
              onPressed: () => onRun(title),
              icon: const Icon(Icons.play_arrow_rounded),
            ),
    );
  }
}
