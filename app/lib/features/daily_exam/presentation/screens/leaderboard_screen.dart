import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/bd_time.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/daily_exam/application/leaderboard_providers.dart';
import 'package:prostuti/features/daily_exam/data/daily_standing.dart';
import 'package:prostuti/features/daily_exam/data/leaderboard_repository.dart';
import 'package:prostuti/features/daily_exam/presentation/widgets/standing_widgets.dart';
import 'package:prostuti/features/feed/presentation/screens/compose_post_screen.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';

/// My private daily-exam standing for the last 7 Bangladesh days: a hero
/// with my rank, Top %, score and the day's top score, and an anonymous
/// ladder of the scores around mine. Nobody else's identity is shown.
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  late final List<DateTime> _days = lastBdDays(7);
  late String _date = BdTime.toIsoDate(_days.first);

  bool get _isToday => _date == BdTime.toIsoDate(_days.first);

  void _retry() => ref.invalidate(dailyLeaderboardProvider(_date));

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final async = ref.watch(dailyLeaderboardProvider(_date));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.dailyExamLeaderboardTitle),
            Text(
              l.dailyExamLeaderboardSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _DateChips(days: _days, selected: _date, onSelected: (d) => setState(() => _date = d)),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => refreshLeaderboard(ref, _date),
              child: switch (async) {
                AsyncValue(:final value?) => _StandingBody(
                  standing: value,
                  isToday: _isToday,
                  onRefresh: () => unawaited(refreshLeaderboard(ref, _date)),
                ),
                AsyncValue(:final error?) => _FullHeight(
                  child: ErrorView(error: error, onRetry: _retry),
                ),
                _ => const _StandingSkeleton(),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DateChips extends StatelessWidget {
  const _DateChips({required this.days, required this.selected, required this.onSelected});

  final List<DateTime> days;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final locale = context.isBn ? 'bn' : 'en';
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.sm),
        itemCount: days.length,
        separatorBuilder: (_, _) => Gap.w8,
        itemBuilder: (context, i) {
          final iso = BdTime.toIsoDate(days[i]);
          final label = switch (i) {
            0 => l.today,
            1 => l.dailyExamYesterday,
            _ => DateFormat('d MMM', locale).format(days[i]),
          };
          return ChoiceChip(
            label: Text(label),
            selected: iso == selected,
            showCheckmark: false,
            avatar: i == 0 ? const Icon(Icons.today_rounded, size: 16) : null,
            onSelected: (_) => onSelected(iso),
          );
        },
      ),
    );
  }
}

class _StandingBody extends ConsumerWidget {
  const _StandingBody({required this.standing, required this.isToday, required this.onRefresh});

  final DailyStanding standing;
  final bool isToday;

  /// Bypasses the cache ("no exam yet" is remembered for a minute).
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    if (!standing.hasExam) {
      final early = BdTime.now().hour < 6;
      return _FullHeight(
        child: EmptyView(
          icon: isToday ? Icons.schedule_rounded : Icons.event_busy_rounded,
          title: isToday ? l.dailyExamNoExamTitle : l.dailyExamNoExamPast,
          message: isToday ? (early ? l.dailyExamNoExamEarly : l.dailyExamNoExamLate) : null,
          action: isToday ? onRefresh : null,
          actionLabel: l.dailyNotesRefresh,
        ),
      );
    }

    // Today's rank moves with every submission; a saved one may be behind.
    final offline = !ref.watch(isOnlineProvider.select((v) => v.value ?? ConnectivityService.instance.isOnline));
    final profile = ref.watch(currentProfileProvider).value;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xs, Gap.lg, Gap.xxl),
      children: [
        if (offline && isToday) ...[const _SavedNote(), Gap.h12],
        if (standing.attempted) ...[
          StandingHero(standing: standing),
          Gap.h12,
          FilledButton.icon(
            onPressed: () =>
                unawaited(ComposePostScreen.openDraft(context, standingShareText(context, standing, isToday: isToday))),
            icon: const Icon(Icons.ios_share_rounded),
            label: Text(l.dailyExamShareScore),
          ),
          Gap.h16,
          StandingLadder(standing: standing, myName: profile?.displayName, myAvatarUrl: profile?.avatarUrl),
        ] else ...[
          _NotTakenCard(isToday: isToday, participants: standing.participants),
          Gap.h12,
          _DayStats(standing: standing),
          if (isToday) ...[Gap.h16, const LockedLadder()],
        ],
      ],
    );
  }
}

/// Not attempted: a nudge (and the way in, today).
class _NotTakenCard extends StatelessWidget {
  const _NotTakenCard({required this.isToday, required this.participants});

  final bool isToday;
  final int participants;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = !isToday
        ? null
        : participants == 0
        ? l.dailyExamNoParticipants
        : l.dailyExamNotTakenBody(context.n(participants));
    return Card(
      child: Padding(
        padding: Gap.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(Gap.md),
                  decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: Icon(isToday ? Icons.timer_outlined : Icons.event_busy_rounded, color: scheme.primary),
                ),
                Gap.w12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isToday ? l.dailyExamNotJoinedToday : l.dailyExamNotTakenPast,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (body != null) ...[
                        Gap.h4,
                        Text(body, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (isToday) ...[
              Gap.h16,
              FilledButton.icon(
                onPressed: () => context.push(Routes.dailyExam),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(l.dailyExamTakeNow),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Participants and the day's top score.
class _DayStats extends StatelessWidget {
  const _DayStats({required this.standing});

  final DailyStanding standing;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final best = standing.topScore;
    return Row(
      children: [
        Expanded(
          child: StandingStatTile(
            icon: Icons.groups_rounded,
            label: l.dailyExamParticipantsLabel,
            value: context.n(standing.participants),
          ),
        ),
        Gap.w12,
        Expanded(
          child: StandingStatTile(
            icon: Icons.emoji_events_rounded,
            color: AppColors.gold,
            label: l.dailyExamTopScore,
            value: best == null ? '—' : scoreOutOf(context, best, standing.totalMarks),
          ),
        ),
      ],
    );
  }
}

class _SavedNote extends StatelessWidget {
  const _SavedNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: Radii.button),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 18, color: scheme.onSurfaceVariant),
          Gap.w8,
          Expanded(
            child: Text(
              context.l10n.dailyExamSavedStanding,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _StandingSkeleton extends StatelessWidget {
  const _StandingSkeleton();

  @override
  Widget build(BuildContext context) {
    const rung = Padding(
      padding: EdgeInsets.symmetric(vertical: Gap.sm),
      child: Row(
        children: [
          SkeletonBox(width: 36, height: 36, radius: 18),
          Gap.w12,
          Expanded(child: SkeletonBox()),
          Gap.w12,
          SkeletonBox(width: 48),
        ],
      ),
    );
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xs, Gap.lg, Gap.xxl),
      children: const [
        SkeletonShimmer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SkeletonBox(height: 236, radius: 16),
              Gap.h12,
              SkeletonBox(height: 48, radius: 12),
              Gap.h16,
              rung,
              rung,
              rung,
              rung,
              rung,
            ],
          ),
        ),
      ],
    );
  }
}

/// Full-height scrollable so pull-to-refresh works on empty/error states.
class _FullHeight extends StatelessWidget {
  const _FullHeight({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }
}
