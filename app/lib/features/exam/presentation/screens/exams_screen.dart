import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/config/app_constants.dart';
import 'package:prostuti/core/entitlements/feature_access.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:prostuti/features/exam/application/exam_clock.dart';
import 'package:prostuti/features/exam/application/exam_failure_messages.dart';
import 'package:prostuti/features/exam/application/exam_providers.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/exam/data/exam_repository.dart';
import 'package:prostuti/features/exam/presentation/utils/exam_kind_style.dart';
import 'package:prostuti/features/exam/presentation/utils/exam_title.dart';
import 'package:prostuti/features/exam/presentation/widgets/exam_launcher.dart';
import 'package:prostuti/features/exam/presentation/widgets/feature_tile.dart';

/// Exams tab: resume banner, offline-pending submissions, every exam type,
/// and a strip of recent results.
class ExamsScreen extends ConsumerWidget {
  const ExamsScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref
      ..invalidate(activeExamProvider)
      ..invalidate(recentExamHistoryProvider);
    await Future.wait([
      ref.read(activeExamProvider.future).catchError((Object _) => null),
      ref.read(recentExamHistoryProvider.future).catchError((Object _) => const <ExamHistoryItem>[]),
    ]);
  }

  Future<void> _startSubjectExam(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    List<Subject> subjects;
    try {
      subjects = await ref.read(subjectsProvider.future);
    } on Object catch (e) {
      if (context.mounted) showExamError(context, e);
      return;
    }
    if (!context.mounted) return;
    final choice = await showExamSetupSheet(
      context,
      title: l.examCardSubjectTitle,
      subjects: subjects.where((s) => s.questionCount > 0).toList(),
    );
    if (choice == null || choice.subjectId == null || !context.mounted) return;
    await ExamLauncher.start(
      context,
      ref,
      ExamKind.subject,
      config: {'subject_id': choice.subjectId, 'count': choice.count},
    );
  }

  Future<void> _startWeakExam(BuildContext context, WidgetRef ref) async {
    final choice = await showExamSetupSheet(context, title: context.l10n.examCardWeakTitle);
    if (choice == null || !context.mounted) return;
    await ExamLauncher.start(context, ref, ExamKind.weakTopic, config: {'count': choice.count});
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    registerExamFailureMessages();
    final l = context.l10n;
    final hasDaily = ref.watch(hasFeatureProvider(Features.dailyExam));
    final hasModel = ref.watch(hasFeatureProvider(Features.modelTest));
    final hasSmart = ref.watch(hasFeatureProvider(Features.smartPractice));
    final accessKnown = ref.watch(featureAccessProvider.select((a) => a.hasValue));

    return Scaffold(
      appBar: AppBar(
        title: Text(l.examsTitle),
        actions: [
          IconButton(
            tooltip: l.examCardHistoryTitle,
            icon: const Icon(Icons.history_rounded),
            onPressed: () => context.push(Routes.examHistory),
          ),
          IconButton(
            tooltip: l.examCardLeaderboardTitle,
            icon: const Icon(Icons.leaderboard_rounded),
            onPressed: () => context.push(Routes.leaderboard),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl),
          children: [
            const _PendingSubmissions(),
            const _ActiveExamBanner(),
            const _Hero(),
            SectionHeader(title: l.examStartSection),
            _TileRow(
              left: FeatureTile(
                icon: Icons.newspaper_rounded,
                color: AppColors.brand,
                title: l.examCardDailyTitle,
                subtitle: l.examCardDailyBody,
                premium: accessKnown && !hasDaily,
                onTap: () => context.push(Routes.dailyExam),
              ),
              right: FeatureTile(
                icon: Icons.assignment_rounded,
                color: ExamKind.modelTest.accent,
                title: l.examCardModelTitle,
                subtitle: l.examCardModelBody,
                premium: accessKnown && !hasModel,
                onTap: () => context.push(Routes.modelTests),
              ),
            ),
            Gap.h12,
            _TileRow(
              left: FeatureTile(
                icon: Icons.menu_book_rounded,
                color: ExamKind.subject.accent,
                title: l.examCardSubjectTitle,
                subtitle: l.examCardSubjectBody,
                onTap: () => unawaited(_startSubjectExam(context, ref)),
              ),
              right: FeatureTile(
                icon: Icons.track_changes_rounded,
                color: ExamKind.weakTopic.accent,
                title: l.examCardWeakTitle,
                subtitle: l.examCardWeakBody,
                premium: accessKnown && !hasSmart,
                onTap: () => unawaited(_startWeakExam(context, ref)),
              ),
            ),
            SectionHeader(title: l.examMoreSection),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _LinkTile(
                    icon: Icons.history_rounded,
                    color: AppColors.info,
                    title: l.examCardHistoryTitle,
                    subtitle: l.examCardHistoryBody,
                    onTap: () => context.push(Routes.examHistory),
                  ),
                  const Divider(indent: 72),
                  _LinkTile(
                    icon: Icons.emoji_events_rounded,
                    color: AppColors.gold,
                    title: l.examCardLeaderboardTitle,
                    subtitle: l.examCardLeaderboardBody,
                    onTap: () => context.push(Routes.leaderboard),
                  ),
                ],
              ),
            ),
            SectionHeader(title: l.examRecentTitle, action: l.seeAll, onAction: () => context.push(Routes.examHistory)),
            const _RecentStrip(),
          ],
        ),
      ),
    );
  }
}

class _TileRow extends StatelessWidget {
  const _TileRow({required this.left, required this.right});
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          Gap.w12,
          Expanded(child: right),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: Radii.button),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: Theme.of(context).textTheme.titleSmall),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: Gap.sm),
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        borderRadius: Radii.card,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, Color.lerp(scheme.primary, Colors.black, 0.35)!],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.examsHeroTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.onPrimary),
                ),
                Gap.h4,
                Text(
                  l.examsHeroBody(Fmt.score(AppConstants.defaultNegativeMark, bangla: context.isBn)),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onPrimary.withValues(alpha: 0.9)),
                ),
              ],
            ),
          ),
          Gap.w12,
          Icon(Icons.timer_rounded, size: 48, color: scheme.onPrimary.withValues(alpha: 0.85)),
        ],
      ),
    );
  }
}

/// "Exam in progress" banner with a live countdown.
class _ActiveExamBanner extends ConsumerWidget {
  const _ActiveExamBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(activeExamProvider).value;
    if (session == null || ref.watch(examRepositoryProvider).isSubmissionPending(session.sessionId)) {
      return const SizedBox.shrink();
    }
    return _ActiveExamCard(session: session);
  }
}

class _ActiveExamCard extends ConsumerStatefulWidget {
  const _ActiveExamCard({required this.session});
  final ExamSession session;

  @override
  ConsumerState<_ActiveExamCard> createState() => _ActiveExamCardState();
}

class _ActiveExamCardState extends ConsumerState<_ActiveExamCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (widget.session.remaining == Duration.zero) {
        _timer?.cancel();
        ref.invalidate(activeExamProvider);
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final s = widget.session;
    final answered = ref.read(examRepositoryProvider).savedAnswers(s.sessionId).length;
    final left = ExamTiming.format(s.remaining, bangla: context.isBn);
    return Card(
      margin: const EdgeInsets.only(top: Gap.sm),
      color: scheme.primaryContainer,
      child: InkWell(
        borderRadius: Radii.card,
        onTap: () => context.push(Routes.examSession(s.sessionId)),
        child: Padding(
          padding: Gap.card,
          child: Row(
            children: [
              Icon(Icons.play_circle_fill_rounded, size: 40, color: scheme.onPrimaryContainer),
              Gap.w12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.examResumeTitle,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onPrimaryContainer),
                    ),
                    Text(
                      examTitleOf(context, ref, s.title, s.kind),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(color: scheme.onPrimaryContainer),
                    ),
                    Text(
                      l.examResumeBody(context.n(answered), context.n(s.total), left),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
              Gap.w8,
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => context.push(Routes.examSession(s.sessionId)),
                child: Text(l.examResumeCta),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Exams submitted offline, waiting for connectivity.
class _PendingSubmissions extends ConsumerWidget {
  const _PendingSubmissions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingExamSubmissionsProvider);
    if (pending.isEmpty) return const SizedBox.shrink();
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (final p in pending)
          Card(
            margin: const EdgeInsets.only(top: Gap.sm),
            child: ListTile(
              leading: Icon(Icons.cloud_upload_rounded, color: scheme.primary),
              title: Text(examTitleOf(context, ref, p.title, p.kind), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${l.examPendingTitle} · ${l.examPendingBody(context.n(p.answered), context.n(p.total))}'),
              trailing: const Icon(Icons.schedule_rounded, size: 18),
            ),
          ),
      ],
    );
  }
}

class _RecentStrip extends ConsumerWidget {
  const _RecentStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final value = ref.watch(recentExamHistoryProvider);
    return SizedBox(
      height: 132,
      child: value.when(
        skipLoadingOnRefresh: true,
        loading: () => SkeletonShimmer(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 3,
            separatorBuilder: (_, _) => Gap.w12,
            itemBuilder: (_, _) => const SkeletonBox(width: 200, height: 132, radius: 16),
          ),
        ),
        error: (e, _) => Card(
          child: Center(
            child: TextButton.icon(
              onPressed: () => ref.invalidate(recentExamHistoryProvider),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(failureMessage(context, e), maxLines: 2, textAlign: TextAlign.center),
            ),
          ),
        ),
        data: (items) => items.isEmpty
            ? Card(
                child: Center(
                  child: Padding(
                    padding: Gap.card,
                    child: Text(l.examRecentEmpty, textAlign: TextAlign.center),
                  ),
                ),
              )
            : ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, _) => Gap.w12,
                itemBuilder: (context, i) => _RecentCard(item: items[i]),
              ),
      ),
    );
  }
}

class _RecentCard extends ConsumerWidget {
  const _RecentCard({required this.item});
  final ExamHistoryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bangla = context.isBn;
    final color = scoreColor(item.percent);
    return SizedBox(
      width: 200,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(Routes.examResult(item.sessionId)),
          child: Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(item.kind.icon, size: 18, color: item.kind.accent),
                    Gap.w4,
                    Expanded(
                      child: Text(
                        item.kind.label(context),
                        style: theme.textTheme.labelMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Gap.h4,
                Text(
                  examTitleOf(context, ref, item.title, item.kind),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${Fmt.score(item.score, bangla: bangla)}/${Fmt.score(item.maxScore, bangla: bangla)}',
                      style: theme.textTheme.titleMedium?.copyWith(color: color),
                    ),
                    const Spacer(),
                    Text(
                      Fmt.timeAgo(item.submittedAt, bangla: bangla),
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
