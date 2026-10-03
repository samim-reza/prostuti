import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/app_image.dart';
import 'package:prostuti/features/daily_exam/data/daily_leaderboard.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';

/// Gold / silver / bronze for ranks 1–3, null otherwise.
Color? medalColor(int rank) => switch (rank) {
  1 => AppColors.gold,
  2 => const Color(0xFF9EA7B3),
  3 => const Color(0xFFC07A3F),
  _ => null,
};

String _score(BuildContext context, double score) => Fmt.score(score, bangla: context.isBn);

String? _time(BuildContext context, int? seconds) =>
    seconds == null ? null : Fmt.clock(Duration(seconds: seconds), bangla: context.isBn);

void _openProfile(BuildContext context, String userId) {
  if (userId.isEmpty) return;
  unawaited(context.push(Routes.userProfile(userId)));
}

/// One ranked row: rank, avatar, name, score and time taken.
class LeaderboardRow extends StatelessWidget {
  const LeaderboardRow({required this.entry, this.isMe = false, this.dense = false, super.key});

  final LeaderboardEntry entry;
  final bool isMe;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l = context.l10n;
    final medal = medalColor(entry.rank);
    final time = _time(context, entry.timeTakenSeconds);
    return Material(
      color: isMe ? scheme.primary.withValues(alpha: 0.10) : Colors.transparent,
      borderRadius: const BorderRadius.all(Radii.md),
      child: InkWell(
        borderRadius: const BorderRadius.all(Radii.md),
        onTap: () => _openProfile(context, entry.userId),
        child: Semantics(
          button: true,
          label:
              '${l.dailyExamRankSemantics(context.n(entry.rank))}, ${entry.displayName}, '
              '${l.dailyExamPoints(_score(context, entry.score))}',
          excludeSemantics: true,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: Gap.sm, vertical: dense ? Gap.xs + 2 : Gap.sm),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: medal != null
                      ? Icon(Icons.workspace_premium_rounded, color: medal, size: 26)
                      : Text(
                          context.n(entry.rank),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleSmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                ),
                Gap.w8,
                UserAvatar(name: entry.displayName, url: entry.avatarUrl, radius: dense ? 18 : 20),
                Gap.w12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isMe ? '${entry.displayName} (${l.dailyExamYou})' : entry.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: isMe ? FontWeight.w700 : null),
                      ),
                      if (entry.username.isNotEmpty)
                        Text(
                          '@${entry.username}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                Gap.w8,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      l.dailyExamPoints(_score(context, entry.score)),
                      style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
                    ),
                    if (time != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.timer_outlined, size: 13, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 2),
                          Text(time, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
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

/// "আমার অবস্থান #১২ · ১২৩ জনের মধ্যে" with score and time taken.
class MyRankCard extends StatelessWidget {
  const MyRankCard({required this.standing, required this.participants, this.onTap, this.pinned = false, super.key});

  final MyStanding standing;
  final int participants;
  final VoidCallback? onTap;

  /// Compact variant pinned below a list.
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l = context.l10n;
    final time = _time(context, standing.timeTakenSeconds);
    final medal = medalColor(standing.rank);
    return Card(
      clipBehavior: Clip.antiAlias,
      color: scheme.primaryContainer.withValues(alpha: theme.brightness == Brightness.dark ? 0.4 : 0.7),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: Gap.lg, vertical: pinned ? Gap.md : Gap.lg),
          child: Row(
            children: [
              if (medal != null) ...[
                Icon(Icons.workspace_premium_rounded, color: medal, size: pinned ? 28 : 36),
                Gap.w8,
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.dailyExamMyRank,
                      style: theme.textTheme.labelMedium?.copyWith(color: scheme.onPrimaryContainer),
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: l.dailyExamRank(context.n(standing.rank)),
                            style: (pinned ? theme.textTheme.titleLarge : theme.textTheme.headlineMedium)?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                          if (participants > 0)
                            TextSpan(
                              text: '  ${l.dailyExamRankOf(context.n(participants))}',
                              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onPrimaryContainer),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _Stat(label: l.dailyExamScoreLabel, value: _score(context, standing.score)),
              if (time != null) ...[Gap.w16, _Stat(label: l.dailyExamTimeLabel, value: time)],
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onPrimaryContainer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
        ),
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: color.withValues(alpha: 0.8))),
      ],
    );
  }
}

/// Top-3 podium: 2nd · 1st · 3rd with gold/silver/bronze pedestals.
class LeaderboardPodium extends StatelessWidget {
  const LeaderboardPodium({required this.entries, this.myUserId, super.key});

  /// Up to three entries, in rank order.
  final List<LeaderboardEntry> entries;
  final String? myUserId;

  @override
  Widget build(BuildContext context) {
    LeaderboardEntry? at(int i) => i < entries.length ? entries[i] : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: _PodiumSpot(entry: at(1), place: 2, myUserId: myUserId),
        ),
        Gap.w8,
        Expanded(
          child: _PodiumSpot(entry: at(0), place: 1, myUserId: myUserId),
        ),
        Gap.w8,
        Expanded(
          child: _PodiumSpot(entry: at(2), place: 3, myUserId: myUserId),
        ),
      ],
    );
  }
}

class _PodiumSpot extends StatelessWidget {
  const _PodiumSpot({required this.entry, required this.place, this.myUserId});

  final LeaderboardEntry? entry;
  final int place;
  final String? myUserId;

  @override
  Widget build(BuildContext context) {
    final entry = this.entry;
    if (entry == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l = context.l10n;
    // Medal follows the real rank (ties share one); height follows the spot.
    final color = medalColor(entry.rank) ?? medalColor(place)!;
    final radius = place == 1 ? 36.0 : 28.0;
    final pedestal = switch (place) {
      1 => 84.0,
      2 => 60.0,
      _ => 44.0,
    };
    final isMe = entry.userId == myUserId;
    return Semantics(
      button: true,
      label:
          '${l.dailyExamRankSemantics(context.n(entry.rank))}, ${entry.displayName}, '
          '${l.dailyExamPoints(_score(context, entry.score))}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: const BorderRadius.all(Radii.md),
        onTap: () => _openProfile(context, entry.userId),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (place == 1) Icon(Icons.emoji_events_rounded, color: color, size: 28) else const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 3),
              ),
              child: UserAvatar(name: entry.displayName, url: entry.avatarUrl, radius: radius),
            ),
            Gap.h8,
            Text(
              isMe ? l.dailyExamYou : entry.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall,
            ),
            Text(
              l.dailyExamPoints(_score(context, entry.score)),
              style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
            ),
            if (_time(context, entry.timeTakenSeconds) case final time?)
              Text(time, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            Gap.h8,
            Container(
              height: pedestal,
              width: double.infinity,
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(top: Gap.sm),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [color.withValues(alpha: 0.85), color.withValues(alpha: 0.35)],
                ),
                borderRadius: const BorderRadius.vertical(top: Radii.md),
              ),
              child: Text(
                context.n(entry.rank),
                style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
