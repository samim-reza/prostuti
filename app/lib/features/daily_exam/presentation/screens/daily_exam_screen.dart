import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/entitlements/feature_access.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/bd_time.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/daily_exam/application/leaderboard_providers.dart';
import 'package:prostuti/features/daily_exam/data/daily_standing.dart';
import 'package:prostuti/features/daily_exam/presentation/widgets/standing_widgets.dart';
import 'package:prostuti/features/daily_notes/application/current_affairs_failures.dart';
import 'package:prostuti/features/daily_notes/application/today_notes_controller.dart';
import 'package:prostuti/features/daily_notes/data/daily_note.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/exam/data/exam_repository.dart';

/// Negative marking of the daily exam (`daily_exams.negative_mark` default).
const _negativeMark = 0.5;

/// Today's current-affairs exam: intro + rules + start (one attempt only)
/// with a live count of participants and the top score, or "already taken"
/// with my private rank.
class DailyExamScreen extends StatelessWidget {
  const DailyExamScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.dailyExamTitle),
        actions: [
          IconButton(
            onPressed: () => context.push(Routes.leaderboard),
            tooltip: l.dailyExamLeaderboardTitle,
            icon: const Icon(Icons.leaderboard_rounded),
          ),
          Gap.w4,
        ],
      ),
      body: const EntitlementGate(feature: Features.dailyExam, child: _DailyExamBody()),
    );
  }
}

class _DailyExamBody extends ConsumerStatefulWidget {
  const _DailyExamBody();

  @override
  ConsumerState<_DailyExamBody> createState() => _DailyExamBodyState();
}

class _DailyExamBodyState extends ConsumerState<_DailyExamBody> {
  static const _pollEvery = Duration(seconds: 60);

  Timer? _poll;
  bool _starting = false;
  bool _attemptedLocally = false;
  bool _noExamLocally = false;

  String get _today => BdTime.todayIso();

  @override
  void initState() {
    super.initState();
    registerCurrentAffairsMessages();
    // "Live" preview: re-check once a minute (matches today's cache TTL).
    _poll = Timer.periodic(_pollEvery, (_) {
      if (mounted && ConnectivityService.instance.isOnline) ref.invalidate(dailyLeaderboardProvider(_today));
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _noExamLocally = false);
    ref.invalidate(activeDailySessionProvider);
    await Future.wait([ref.read(todayNotesProvider.notifier).refresh(), refreshLeaderboard(ref, _today)]);
  }

  Future<void> _start({ExamSession? resume}) async {
    if (_starting) return;
    final l = context.l10n;
    final today = ref.read(todayNotesProvider).value;

    if (resume == null) {
      if (!ConnectivityService.instance.isOnline) {
        showInfoSnack(context, l.offlineUnavailable);
        return;
      }
      final minutes = today?.dailyExam?.durationMinutes;
      final ok = await confirmDialog(
        context,
        title: l.dailyExamConfirmTitle,
        message: l.dailyExamConfirmBody(Fmt.minutes(minutes ?? 10, bangla: context.isBn)),
        confirmLabel: l.dailyExamConfirmCta,
      );
      if (!ok || !mounted) return;
    }

    setState(() => _starting = true);
    try {
      final sessionId = resume?.sessionId ?? (await ref.read(examRepositoryProvider).start(ExamKind.daily)).sessionId;
      if (!mounted) return;
      setState(() => _starting = false);
      await context.push(Routes.examSession(sessionId));
      // Back from the exam: my rank and the board have probably changed.
      if (!mounted) return;
      ref.invalidate(activeDailySessionProvider);
      unawaited(refreshLeaderboard(ref, _today));
    } on Object catch (e) {
      if (!mounted) return;
      final failure = AppFailure.from(e);
      switch (failure) {
        case ConflictFailure(code: 'already_attempted'):
          setState(() => _attemptedLocally = true);
          unawaited(refreshLeaderboard(ref, _today));
          showInfoSnack(context, currentAffairsErrorText(context, failure));
        case NotFoundFailure(code: 'no_daily_exam'):
          setState(() => _noExamLocally = true);
        case FeatureLockedFailure():
          showLockedSheet(context);
        case NetworkFailure():
          showInfoSnack(context, l.offlineUnavailable);
        default:
          showInfoSnack(context, currentAffairsErrorText(context, failure));
      }
    } finally {
      if (mounted && _starting) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(todayNotesProvider);
    final standingAsync = ref.watch(dailyLeaderboardProvider(_today));
    final active = ref.watch(activeDailySessionProvider).value;

    final Widget top;
    var preview = false;
    switch (notesAsync) {
      case AsyncValue(:final value?):
        final exam = _noExamLocally ? null : value.dailyExam;
        final standing = standingAsync.value;
        if (_attemptedLocally || (standing?.attempted ?? false)) {
          top = _AttemptedSection(standing: standing);
        } else if (exam == null) {
          top = _NoExamCard(onRefresh: _refresh);
        } else {
          top = _IntroSection(exam: exam, active: active, starting: _starting, onStart: _start);
          preview = true;
        }
      case AsyncValue(:final error?):
        top = ErrorView(error: error, onRetry: () => ref.invalidate(todayNotesProvider), compact: true);
      default:
        top = const _IntroSkeleton();
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl),
        children: [
          top,
          if (preview) ...[
            Gap.h24,
            _StandingPreview(standing: standingAsync, onRetry: () => ref.invalidate(dailyLeaderboardProvider(_today))),
          ],
        ],
      ),
    );
  }
}

class _IntroSection extends StatelessWidget {
  const _IntroSection({required this.exam, required this.active, required this.starting, required this.onStart});

  final DailyExamInfo exam;
  final ExamSession? active;
  final bool starting;
  final Future<void> Function({ExamSession? resume}) onStart;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bangla = context.isBn;
    final active = this.active;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ExamHero(exam: exam),
        Gap.h16,
        Card(
          child: Padding(
            padding: Gap.card,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.dailyExamRulesTitle, style: theme.textTheme.titleSmall),
                Gap.h12,
                _Rule(icon: Icons.looks_one_rounded, text: l.dailyExamRuleOnce, emphasized: true),
                _Rule(
                  icon: Icons.remove_circle_outline_rounded,
                  text: l.dailyExamRuleNegative(Fmt.score(_negativeMark, bangla: bangla)),
                ),
                _Rule(icon: Icons.timer_off_outlined, text: l.dailyExamRuleAutoSubmit),
                _Rule(icon: Icons.leaderboard_rounded, text: l.dailyExamRuleRanking),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => context.push(Routes.notes),
                    icon: const Icon(Icons.menu_book_rounded, size: 18),
                    label: Text(l.dailyExamReadNotes),
                  ),
                ),
              ],
            ),
          ),
        ),
        Gap.h16,
        if (active != null) ...[
          Row(
            children: [
              Icon(Icons.play_circle_outline_rounded, size: 18, color: scheme.primary),
              Gap.w8,
              Expanded(
                child: Text(l.dailyExamResumeHint, style: theme.textTheme.bodySmall?.copyWith(color: scheme.primary)),
              ),
            ],
          ),
          Gap.h8,
        ],
        FilledButton.icon(
          onPressed: starting ? null : () => onStart(resume: active),
          icon: starting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
              : Icon(active != null ? Icons.play_circle_fill_rounded : Icons.play_arrow_rounded),
          label: Text(active != null ? l.dailyExamResume : l.dailyExamStart),
        ),
      ],
    );
  }
}

class _ExamHero extends StatelessWidget {
  const _ExamHero({required this.exam});

  final DailyExamInfo exam;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final bangla = context.isBn;
    const onHero = Colors.white;
    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: const BoxDecoration(
        borderRadius: Radii.card,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brand, AppColors.brandDark],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(Gap.sm),
                decoration: BoxDecoration(
                  color: onHero.withValues(alpha: 0.15),
                  borderRadius: const BorderRadius.all(Radii.md),
                ),
                child: const Icon(Icons.newspaper_rounded, color: onHero),
              ),
              Gap.w12,
              Expanded(
                child: Text(
                  Fmt.date(DateTime.now(), bangla: bangla),
                  style: theme.textTheme.labelLarge?.copyWith(color: onHero.withValues(alpha: 0.85)),
                ),
              ),
            ],
          ),
          Gap.h12,
          Text(
            exam.titleFor(bangla: bangla),
            style: theme.textTheme.titleLarge?.copyWith(color: onHero),
          ),
          Gap.h16,
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  icon: Icons.help_outline_rounded,
                  label: l.dailyExamQuestionsLabel,
                  value: l.dailyExamQuestionsValue(context.n(exam.questionCount)),
                ),
              ),
              Gap.w8,
              Expanded(
                child: _HeroStat(
                  icon: Icons.timer_outlined,
                  label: l.dailyExamDurationLabel,
                  value: Fmt.minutes(exam.durationMinutes, bangla: bangla),
                ),
              ),
              Gap.w8,
              Expanded(
                child: _HeroStat(
                  icon: Icons.remove_circle_outline_rounded,
                  label: l.dailyExamNegativeLabel,
                  value: l.dailyExamNegativeValue(Fmt.score(_negativeMark, bangla: bangla)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const onHero = Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.md),
      decoration: BoxDecoration(color: onHero.withValues(alpha: 0.12), borderRadius: const BorderRadius.all(Radii.md)),
      child: Column(
        children: [
          Icon(icon, color: onHero, size: 20),
          Gap.h4,
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(color: onHero, fontWeight: FontWeight.w700),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: onHero.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.icon, required this.text, this.emphasized = false});

  final IconData icon;
  final String text;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: emphasized ? scheme.error : scheme.primary),
          Gap.w12,
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: emphasized ? FontWeight.w700 : null),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttemptedSection extends StatelessWidget {
  const _AttemptedSection({required this.standing});

  /// Null while loading (or unknown, offline without a saved copy).
  final DailyStanding? standing;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final standing = this.standing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Gap.xl),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(Gap.md),
                  decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: const Icon(Icons.task_alt_rounded, size: 40, color: AppColors.success),
                ),
                Gap.h16,
                Text(l.dailyExamAttemptedTitle, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
                Gap.h8,
                Text(
                  l.dailyExamAttemptedBody,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        if (standing != null && standing.attempted) ...[
          Gap.h12,
          StandingSummaryCard(standing: standing, onTap: () => context.push(Routes.leaderboard)),
        ],
        Gap.h16,
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => context.push(Routes.leaderboard),
                icon: const Icon(Icons.leaderboard_rounded),
                label: Text(l.dailyExamViewLeaderboard),
              ),
            ),
            Gap.w12,
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.push(Routes.examHistory),
                icon: const Icon(Icons.history_rounded),
                label: Text(l.dailyExamHistory),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NoExamCard extends StatelessWidget {
  const _NoExamCard({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // Published around 05:50 Bangladesh time by the pipeline.
    final early = BdTime.now().hour < 6;
    return Card(
      child: Column(
        children: [
          EmptyView(
            icon: Icons.schedule_rounded,
            title: l.dailyExamNoExamTitle,
            message: early ? l.dailyExamNoExamEarly : l.dailyExamNoExamLate,
            action: () => unawaited(onRefresh()),
            actionLabel: l.dailyNotesRefresh,
            compact: true,
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: TextButton.icon(
              onPressed: () => context.push(Routes.notes),
              icon: const Icon(Icons.menu_book_rounded, size: 18),
              label: Text(l.dailyNotesTitle),
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroSkeleton extends StatelessWidget {
  const _IntroSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonBox(height: 190, radius: 16),
          Gap.h16,
          SkeletonBox(height: 170, radius: 16),
          Gap.h16,
          SkeletonBox(height: 50, radius: 12),
        ],
      ),
    );
  }
}

/// Before the exam: today's participants and top score, live. Ranks are
/// private, so there is no list of names.
class _StandingPreview extends StatelessWidget {
  const _StandingPreview({required this.standing, required this.onRetry});

  final AsyncValue<DailyStanding> standing;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = standing.value;

    final Widget content;
    if (value != null) {
      final best = value.topScore;
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: StandingStatTile(
                  icon: Icons.groups_rounded,
                  label: l.dailyExamParticipantsLabel,
                  value: context.n(value.participants),
                ),
              ),
              Gap.w8,
              Expanded(
                child: StandingStatTile(
                  icon: Icons.emoji_events_rounded,
                  color: AppColors.gold,
                  label: l.dailyExamTopScore,
                  value: best == null ? '—' : scoreOutOf(context, best, value.totalMarks),
                ),
              ),
            ],
          ),
          Gap.h12,
          Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 18, color: scheme.onSurfaceVariant),
              Gap.w8,
              Expanded(
                child: Text(
                  value.isEmpty ? l.dailyExamNoParticipants : l.dailyExamGetYourRank,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      );
    } else if (standing.hasError) {
      content = ErrorView(error: standing.error!, onRetry: onRetry, compact: true);
    } else {
      content = const SkeletonShimmer(
        child: Row(
          children: [
            Expanded(child: SkeletonBox(height: 64, radius: 12)),
            Gap.w8,
            Expanded(child: SkeletonBox(height: 64, radius: 12)),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(width: Gap.xs),
                Icon(Icons.leaderboard_rounded, size: 20, color: scheme.primary),
                Gap.w8,
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          l.dailyExamTodayStanding,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      Gap.w8,
                      const _LiveDot(),
                    ],
                  ),
                ),
                TextButton(onPressed: () => context.push(Routes.leaderboard), child: Text(l.seeAll)),
              ],
            ),
            Gap.h4,
            content,
          ],
        ),
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: Radii.chip),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            context.l10n.dailyExamLive,
            style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
