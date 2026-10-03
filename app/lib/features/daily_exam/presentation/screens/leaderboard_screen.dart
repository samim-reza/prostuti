import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/bd_time.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/daily_exam/application/leaderboard_providers.dart';
import 'package:prostuti/features/daily_exam/data/daily_leaderboard.dart';
import 'package:prostuti/features/daily_exam/data/leaderboard_repository.dart';
import 'package:prostuti/features/daily_exam/presentation/widgets/leaderboard_widgets.dart';

/// Daily-exam leaderboard for the last 7 Bangladesh days: podium, ranked
/// list, and my rank pinned at the bottom when I'm outside the list.
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  late final List<DateTime> _days = lastBdDays(7);
  late String _date = BdTime.toIsoDate(_days.first);

  bool get _isToday => _date == BdTime.toIsoDate(_days.first);

  LeaderboardQuery get _query => (date: _date, limit: LeaderboardRepository.maxLimit);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final async = ref.watch(dailyLeaderboardProvider(_query));
    final myId = ref.watch(currentUserIdProvider);
    final board = async.value;
    final pinned = board == null ? null : pinnedStanding(board, myId);
    final notJoinedToday = _isToday && board != null && board.me == null;

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
              onRefresh: () => refreshLeaderboard(ref, _query),
              child: switch (async) {
                AsyncValue(:final value?) =>
                  value.isEmpty ? _EmptyBoard(isToday: _isToday) : _BoardList(board: value, myUserId: myId),
                AsyncValue(:final error?) => _FullHeight(
                  child: ErrorView(error: error, onRetry: () => ref.invalidate(dailyLeaderboardProvider(_query))),
                ),
                _ => const SkeletonList(itemCount: 8),
              },
            ),
          ),
          if (pinned != null)
            _BottomBar(
              child: MyRankCard(standing: pinned, participants: board!.participants, pinned: true),
            )
          else if (board != null && notJoinedToday && !board.isEmpty)
            const _BottomBar(child: _JoinTodayCard()),
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

class _BoardList extends StatelessWidget {
  const _BoardList({required this.board, required this.myUserId});

  final DailyLeaderboard board;
  final String? myUserId;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final rest = board.rest;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xs, Gap.lg, 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Icon(Icons.groups_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
                Gap.w8,
                Text(
                  l.dailyExamParticipants(context.n(board.participants)),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.sm),
          sliver: SliverToBoxAdapter(
            child: LeaderboardPodium(entries: board.podium, myUserId: myUserId),
          ),
        ),
        if (rest.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.sm, Gap.sm, Gap.xl),
            sliver: SliverList.builder(
              itemCount: rest.length,
              itemBuilder: (context, i) => LeaderboardRow(entry: rest[i], isMe: rest[i].userId == myUserId),
            ),
          )
        else
          const SliverToBoxAdapter(child: Gap.h24),
      ],
    );
  }
}

class _EmptyBoard extends StatelessWidget {
  const _EmptyBoard({required this.isToday});

  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return _FullHeight(
      child: EmptyView(
        icon: Icons.emoji_events_outlined,
        title: isToday ? l.dailyExamLeaderboardEmptyToday : l.dailyExamLeaderboardEmptyPast,
        message: isToday ? l.dailyExamNoParticipants : null,
        action: isToday ? () => context.push(Routes.dailyExam) : null,
        actionLabel: l.dailyExamTakeNow,
      ),
    );
  }
}

class _JoinTodayCard extends StatelessWidget {
  const _JoinTodayCard();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.sm, Gap.sm),
        child: Row(
          children: [
            Icon(Icons.timer_outlined, color: theme.colorScheme.primary),
            Gap.w12,
            Expanded(child: Text(l.dailyExamNotJoinedToday, style: theme.textTheme.bodyMedium)),
            Gap.w8,
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => context.push(Routes.dailyExam),
              child: Text(l.dailyExamTakeNow),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        boxShadow: [BoxShadow(color: theme.colorScheme.shadow.withValues(alpha: 0.08), blurRadius: 12)],
      ),
      child: SafeArea(
        top: false,
        child: Padding(padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.sm), child: child),
      ),
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
