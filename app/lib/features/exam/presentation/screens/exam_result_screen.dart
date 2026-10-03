import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/exam/application/exam_failure_messages.dart';
import 'package:prostuti/features/exam/application/exam_providers.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/exam/data/exam_repository.dart';
import 'package:prostuti/features/exam/presentation/utils/exam_kind_style.dart';
import 'package:prostuti/features/exam/presentation/utils/exam_title.dart';
import 'package:prostuti/features/exam/presentation/widgets/exam_launcher.dart';
import 'package:prostuti/features/exam/presentation/widgets/score_ring.dart';

/// Score card after an exam: animated score and percentage ring, correct /
/// wrong / skipped tiles, negative-marking deduction, per-subject bars, the
/// daily rank, and actions (review, share, retake, home). Cached → offline.
class ExamResultScreen extends ConsumerWidget {
  const ExamResultScreen({required this.sessionId, super.key});
  final String sessionId;

  Future<void> _refresh(WidgetRef ref) async {
    if (ConnectivityService.instance.isOnline) {
      try {
        await ref.read(examRepositoryProvider).resultCached(sessionId, force: true);
      } on Object {
        // Keep showing the cached result.
      }
    }
    ref.invalidate(examResultProvider(sessionId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    registerExamFailureMessages();
    final l = context.l10n;
    final value = ref.watch(examResultProvider(sessionId));
    return Scaffold(
      appBar: AppBar(
        title: Text(l.examResultTitle),
        actions: [
          IconButton(
            tooltip: l.examResultHome,
            icon: const Icon(Icons.home_outlined),
            onPressed: () => context.go(Routes.home),
          ),
        ],
      ),
      body: AsyncView<ExamResult>(
        value: value,
        loading: const SkeletonCards(count: 4, height: 140),
        onRetry: () => ref.invalidate(examResultProvider(sessionId)),
        data: (r) => RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl),
            children: [
              _ScoreHero(result: r),
              Gap.h12,
              _CountTiles(result: r),
              Gap.h12,
              _DetailsCard(result: r),
              if (r.rank != null) ...[Gap.h12, _RankCard(result: r)],
              if (r.perSubject.isNotEmpty) ...[Gap.h12, _SubjectBars(result: r)],
              Gap.h24,
              _Actions(result: r),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreHero extends ConsumerWidget {
  const _ScoreHero({required this.result});
  final ExamResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final bangla = context.isBn;
    final color = scoreColor(result.percent);
    final message = switch (result.percent) {
      >= 80 => l.examResultGreat,
      >= 60 => l.examResultGood,
      >= 40 => l.examResultFair,
      _ => l.examResultLow,
    };
    return Card(
      child: Padding(
        padding: Gap.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(result.kind.icon, size: 18, color: result.kind.accent),
                Gap.w8,
                Expanded(
                  child: Text(
                    examTitleOf(context, ref, result.title, result.kind),
                    style: theme.textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Gap.h16,
            Row(
              children: [
                ScoreRing(
                  value: result.percent / 100,
                  color: color,
                  size: 112,
                  stroke: 10,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: result.percent),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => Text(
                      Fmt.percent(v, bangla: bangla),
                      style: theme.textTheme.titleLarge?.copyWith(color: color),
                    ),
                  ),
                ),
                Gap.w16,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.examResultScoreLabel, style: theme.textTheme.labelLarge),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: result.score),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOutCubic,
                        builder: (context, v, _) => Text(
                          Fmt.score((v * 2).round() / 2, bangla: bangla),
                          style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700, color: color),
                        ),
                      ),
                      Text(
                        l.examResultOutOf(Fmt.score(result.maxScore, bangla: bangla)),
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Gap.h12,
            Text(message, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _CountTiles extends StatelessWidget {
  const _CountTiles({required this.result});
  final ExamResult result;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: _Tile(
            icon: Icons.check_circle_rounded,
            color: AppColors.success,
            label: l.examResultCorrect,
            value: context.n(result.correct),
          ),
        ),
        Gap.w8,
        Expanded(
          child: _Tile(
            icon: Icons.cancel_rounded,
            color: scheme.error,
            label: l.examResultWrong,
            value: context.n(result.wrong),
          ),
        ),
        Gap.w8,
        Expanded(
          child: _Tile(
            icon: Icons.remove_circle_outline_rounded,
            color: scheme.outline,
            label: l.examResultSkipped,
            value: context.n(result.skipped),
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.color, required this.label, required this.value});
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Gap.md, horizontal: Gap.sm),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: Radii.card),
        child: Column(
          children: [
            Icon(icon, color: color),
            Gap.h4,
            Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color)),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.result});
  final ExamResult result;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final bangla = context.isBn;
    final deduction = result.wrong * result.negativeMark;
    final time = result.timeTakenSeconds;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.xs),
        child: Column(
          children: [
            _DetailRow(
              icon: Icons.track_changes_rounded,
              label: l.examResultAccuracy,
              value: Fmt.percent(result.accuracy, bangla: bangla),
            ),
            _DetailRow(
              icon: Icons.remove_circle_outline_rounded,
              label: l.examResultNegative(Fmt.score(deduction, bangla: bangla)),
              valueColor: deduction > 0 ? Theme.of(context).colorScheme.error : null,
              value: deduction > 0 ? '−${Fmt.score(deduction, bangla: bangla)}' : Fmt.score(0, bangla: bangla),
            ),
            if (time != null)
              _DetailRow(
                icon: Icons.timer_outlined,
                label: l.examResultTime,
                value: Fmt.clock(Duration(seconds: time), bangla: bangla),
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label, required this.value, this.valueColor});
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      trailing: Text(value, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: valueColor)),
    );
  }
}

class _RankCard extends StatelessWidget {
  const _RankCard({required this.result});
  final ExamResult result;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Card(
      color: AppColors.gold.withValues(alpha: 0.12),
      child: Padding(
        padding: Gap.card,
        child: Row(
          children: [
            const Icon(Icons.emoji_events_rounded, color: AppColors.gold, size: 36),
            Gap.w12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.examResultRank, style: theme.textTheme.labelLarge),
                  Text(
                    l.examResultRankValue(context.n(result.rank ?? 0), context.n(result.participants ?? 0)),
                    style: theme.textTheme.titleLarge,
                  ),
                ],
              ),
            ),
            TextButton(onPressed: () => context.push(Routes.leaderboard), child: Text(l.examResultLeaderboard)),
          ],
        ),
      ),
    );
  }
}

class _SubjectBars extends StatelessWidget {
  const _SubjectBars({required this.result});
  final ExamResult result;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: Gap.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.examResultPerSubject, style: theme.textTheme.titleMedium),
            Gap.h12,
            for (final s in result.perSubject) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.isBn ? s.nameBn : s.nameEn,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    Fmt.percent(s.accuracy * 100, bangla: context.isBn),
                    style: theme.textTheme.labelLarge?.copyWith(color: scoreColor(s.accuracy * 100)),
                  ),
                ],
              ),
              Gap.h4,
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: s.accuracy),
                duration: const Duration(milliseconds: 700),
                builder: (_, v, _) => ClipRRect(
                  borderRadius: Radii.chip,
                  child: LinearProgressIndicator(
                    value: v,
                    minHeight: 8,
                    color: scoreColor(s.accuracy * 100),
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
              Gap.h4,
              Text(
                l.examResultSubjectLine(context.n(s.correct), context.n(s.wrong), context.n(s.total)),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              Gap.h12,
            ],
          ],
        ),
      ),
    );
  }
}

class _Actions extends ConsumerStatefulWidget {
  const _Actions({required this.result});
  final ExamResult result;

  @override
  ConsumerState<_Actions> createState() => _ActionsState();
}

class _ActionsState extends ConsumerState<_Actions> {
  bool _sharing = false;

  Future<void> _share() async {
    final l = context.l10n;
    if (!ConnectivityService.instance.isOnline) {
      showInfoSnack(context, l.offlineUnavailable);
      return;
    }
    final body = await showDialog<String>(context: context, builder: (_) => const _ShareDialog());
    if (body == null || !mounted) return;
    setState(() => _sharing = true);
    try {
      final postId = await ref
          .read(examRepositoryProvider)
          .shareResult(widget.result.sessionId, body: body.isEmpty ? null : body);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l.examResultShared),
            action: SnackBarAction(label: l.examResultView, onPressed: () => context.push(Routes.postDetail(postId))),
          ),
        );
    } on Object catch (e) {
      if (mounted) showExamError(context, e);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final r = widget.result;
    final setup = ref.watch(examSetupProvider(r.sessionId)).value;
    final canRetake = setup != null && setup.canRetake;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: () => context.push(Routes.examReview(r.sessionId)),
          icon: const Icon(Icons.fact_check_rounded),
          label: Text(l.examResultReview),
        ),
        Gap.h12,
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _sharing ? null : () => unawaited(_share()),
                icon: _sharing
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.share_rounded),
                label: Text(l.examResultShare, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            if (canRetake) ...[
              Gap.w12,
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => unawaited(
                    ExamLauncher.start(context, ref, setup.kind, config: setup.retakeConfig, replace: true),
                  ),
                  icon: const Icon(Icons.replay_rounded),
                  label: Text(l.examResultRetake, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ],
        ),
        Gap.h8,
        TextButton.icon(
          onPressed: () => context.go(Routes.home),
          icon: const Icon(Icons.home_rounded),
          label: Text(l.examResultHome),
        ),
      ],
    );
  }
}

class _ShareDialog extends StatefulWidget {
  const _ShareDialog();

  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.examResultShareTitle),
      content: TextField(
        controller: _controller,
        maxLength: 500,
        minLines: 2,
        maxLines: 4,
        decoration: InputDecoration(hintText: l.examResultShareHint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(l.share),
        ),
      ],
    );
  }
}
