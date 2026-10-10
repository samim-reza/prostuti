import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/app_image.dart';
import 'package:prostuti/features/daily_exam/data/daily_standing.dart';

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

/// "১৩.৫/১৫" — or just the score when the full marks are unknown.
String scoreOutOf(BuildContext context, double score, int? total) =>
    total == null ? _score(context, score) : '${_score(context, score)}/${context.n(total)}';

/// The community post draft for a result, e.g. "আজকের দৈনিক সাম্প্রতিক
/// পরীক্ষায় আমার র‍্যাংক ১২/৩৪০, স্কোর ১৩.৫/১৫ 🎯 #প্রস্তুতি".
String standingShareText(BuildContext context, DailyStanding standing, {required bool isToday}) {
  final l = context.l10n;
  final me = standing.me!;
  final rank = context.n(me.rank);
  final participants = context.n(standing.participants);
  final score = scoreOutOf(context, me.score, standing.totalMarks);
  if (isToday) return l.dailyExamShareToday(rank, participants, score);
  // Parsed as UTC so the Bangladesh calendar day never shifts.
  final day = DateTime.tryParse('${standing.date}T00:00:00Z');
  final date = day == null ? standing.date : DateFormat('d MMMM', context.isBn ? 'bn' : 'en').format(day);
  return l.dailyExamShareOnDate(date, rank, participants, score);
}

// -----------------------------------------------------------------------------
// Hero
// -----------------------------------------------------------------------------

/// Big "#12 · out of 340 participants · Top 4%" card with my score, time
/// taken and the day's top score.
class StandingHero extends StatelessWidget {
  const StandingHero({required this.standing, super.key});

  /// Must have [DailyStanding.me].
  final DailyStanding standing;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    const onHero = Colors.white;
    final me = standing.me!;
    final medal = medalColor(me.rank);
    final top = standing.topPercent;
    final score = scoreOutOf(context, me.score, standing.totalMarks);
    final time = _time(context, me.timeTakenSeconds);
    final label = [
      '${l.dailyExamMyRank} ${l.dailyExamRank(context.n(me.rank))}',
      l.dailyExamOfParticipants(context.n(standing.participants)),
      if (top != null) l.dailyExamTopPercent(context.n(top)),
      '${l.dailyExamScoreLabel} $score',
      if (time != null) '${l.dailyExamTimeLabel} $time',
      if (standing.topScore case final best?)
        '${l.dailyExamTopScore} ${scoreOutOf(context, best, standing.totalMarks)}',
    ].join(', ');

    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(
          borderRadius: Radii.card,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.brand, AppColors.brandDark],
          ),
        ),
        child: Stack(
          children: [
            PositionedDirectional(
              end: -28,
              bottom: -32,
              child: Icon(Icons.emoji_events_rounded, size: 168, color: onHero.withValues(alpha: 0.07)),
            ),
            Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.dailyExamMyRank,
                          style: theme.textTheme.labelLarge?.copyWith(color: onHero.withValues(alpha: 0.85)),
                        ),
                      ),
                      TopScoreChip(topScore: standing.topScore, totalMarks: standing.totalMarks, onHero: true),
                    ],
                  ),
                  Gap.h8,
                  Row(
                    children: [
                      if (medal != null) ...[Icon(Icons.workspace_premium_rounded, color: medal, size: 44), Gap.w8],
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            l.dailyExamRank(context.n(me.rank)),
                            style: theme.textTheme.displayMedium?.copyWith(
                              color: onHero,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    l.dailyExamOfParticipants(context.n(standing.participants)),
                    style: theme.textTheme.bodyMedium?.copyWith(color: onHero.withValues(alpha: 0.85)),
                  ),
                  if (top != null) ...[Gap.h12, TopPercentPill(percent: top)],
                  Gap.h16,
                  Row(
                    children: [
                      Expanded(
                        child: _HeroStat(icon: Icons.task_alt_rounded, label: l.dailyExamScoreLabel, value: score),
                      ),
                      Gap.w8,
                      Expanded(
                        child: _HeroStat(icon: Icons.timer_outlined, label: l.dailyExamTimeLabel, value: time ?? '—'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm + 2),
      decoration: BoxDecoration(color: onHero.withValues(alpha: 0.12), borderRadius: const BorderRadius.all(Radii.md)),
      child: Row(
        children: [
          Icon(icon, color: onHero, size: 20),
          Gap.w8,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(color: onHero, fontWeight: FontWeight.w700),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: onHero.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Gold "Top 4%" pill.
class TopPercentPill extends StatelessWidget {
  const TopPercentPill({required this.percent, super.key});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Dark ink on gold reads well on the green hero and on plain surfaces.
    const ink = Color(0xFF3B2A00);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.xs),
      decoration: const BoxDecoration(color: AppColors.gold, borderRadius: Radii.chip),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.trending_up_rounded, size: 16, color: ink),
          Gap.w4,
          Text(
            context.l10n.dailyExamTopPercent(context.n(percent)),
            style: theme.textTheme.labelLarge?.copyWith(color: ink, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// "🏆 Top score 15/15" chip (on the green hero or on a plain surface).
class TopScoreChip extends StatelessWidget {
  const TopScoreChip({required this.topScore, this.totalMarks, this.onHero = false, super.key});

  final double? topScore;
  final int? totalMarks;
  final bool onHero;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final best = topScore;
    final value = best == null ? '—' : scoreOutOf(context, best, totalMarks);
    final fg = onHero ? Colors.white : theme.colorScheme.onSurface;
    return Semantics(
      label: '${l.dailyExamTopScore} $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Gap.sm + 2, vertical: Gap.xs + 2),
        decoration: BoxDecoration(
          color: onHero ? Colors.white.withValues(alpha: 0.16) : AppColors.gold.withValues(alpha: 0.16),
          borderRadius: Radii.chip,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_rounded, size: 16, color: AppColors.gold),
            Gap.w4,
            Text(l.dailyExamTopScore, style: theme.textTheme.labelMedium?.copyWith(color: fg.withValues(alpha: 0.85))),
            Gap.w4,
            Text(
              value,
              style: theme.textTheme.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small labelled number (participants, top score) on a plain surface.
class StandingStatTile extends StatelessWidget {
  const StandingStatTile({required this.icon, required this.label, required this.value, this.color, super.key});

  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tint = color ?? scheme.primary;
    return Semantics(
      container: true,
      label: '$label $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(Gap.md),
        decoration: BoxDecoration(color: tint.withValues(alpha: 0.08), borderRadius: Radii.button),
        child: Row(
          children: [
            Icon(icon, color: tint, size: 22),
            Gap.w8,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact "my rank" card (daily-exam page): rank, participants, Top %,
/// score, time and the top score.
class StandingSummaryCard extends StatelessWidget {
  const StandingSummaryCard({required this.standing, this.onTap, super.key});

  /// Must have [DailyStanding.me].
  final DailyStanding standing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l = context.l10n;
    final me = standing.me!;
    final time = _time(context, me.timeTakenSeconds);
    final medal = medalColor(me.rank);
    final top = standing.topPercent;
    final onCard = scheme.onPrimaryContainer;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: scheme.primaryContainer.withValues(alpha: theme.brightness == Brightness.dark ? 0.4 : 0.7),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (medal != null) ...[Icon(Icons.workspace_premium_rounded, color: medal, size: 36), Gap.w8],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.dailyExamMyRank, style: theme.textTheme.labelMedium?.copyWith(color: onCard)),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: l.dailyExamRank(context.n(me.rank)),
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: onCard,
                                ),
                              ),
                              if (standing.participants > 0)
                                TextSpan(
                                  text: '  ${l.dailyExamRankOf(context.n(standing.participants))}',
                                  style: theme.textTheme.bodySmall?.copyWith(color: onCard),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _Stat(label: l.dailyExamScoreLabel, value: scoreOutOf(context, me.score, standing.totalMarks)),
                  if (time != null) ...[Gap.w16, _Stat(label: l.dailyExamTimeLabel, value: time)],
                ],
              ),
              Gap.h12,
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (top != null) TopPercentPill(percent: top),
                  TopScoreChip(topScore: standing.topScore, totalMarks: standing.totalMarks),
                ],
              ),
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

// -----------------------------------------------------------------------------
// Ladder
// -----------------------------------------------------------------------------

/// Rank badges are 36 wide after an 8 px inset: the rail runs through their
/// centres.
const _badgeSize = 36.0;
const _railStart = Gap.sm + _badgeSize / 2 - 1;

/// "Where you stand": the anonymous rows just above and below mine, my own
/// row crisp and highlighted. Others are only a rank and a score; their
/// avatar and name are an unreadable blur.
class StandingLadder extends StatelessWidget {
  const StandingLadder({required this.standing, this.myName, this.myAvatarUrl, super.key});

  /// Must have [DailyStanding.me].
  final DailyStanding standing;
  final String? myName;
  final String? myAvatarUrl;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final me = standing.me!;
    final gap = standing.gapToNext;
    var seed = 0;
    final rungs = <Widget>[
      if (standing.topOutOfView) ...[
        _Rung(rank: 1, score: standing.topScore ?? me.score, seed: seed++),
        if (standing.gapBelowTop) const _LadderGap(),
      ],
      for (final r in standing.above) _Rung(rank: r.rank, score: r.score, seed: seed++),
      _MyRung(me: me, name: myName, avatarUrl: myAvatarUrl),
      for (final r in standing.below) _Rung(rank: r.rank, score: r.score, seed: seed++),
      if (standing.hasMoreBelow) const _LadderGap(),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.lg, Gap.sm, Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: Gap.sm),
              child: _LadderHeader(),
            ),
            Gap.h12,
            Stack(
              children: [
                // The rail joining the rungs.
                PositionedDirectional(
                  start: _railStart,
                  top: Gap.xl,
                  bottom: Gap.xl,
                  child: Container(width: 2, color: scheme.outlineVariant),
                ),
                Column(children: rungs),
              ],
            ),
            if (gap != null) ...[
              Gap.h8,
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                child: Row(
                  children: [
                    Icon(Icons.trending_up_rounded, size: 18, color: scheme.primary),
                    Gap.w8,
                    Expanded(
                      child: Text(
                        l.dailyExamBehindNext(_score(context, gap.marks), context.n(gap.rank)),
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
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

class _LadderHeader extends StatelessWidget {
  const _LadderHeader();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Icon(Icons.stairs_rounded, size: 22, color: scheme.primary),
        Gap.w8,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.dailyExamLadderTitle, style: theme.textTheme.titleSmall),
              Text(
                l.dailyExamLadderPrivacy,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Gap.w8,
        Icon(Icons.lock_outline_rounded, size: 18, color: scheme.onSurfaceVariant),
      ],
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank, this.mine = false});

  final int rank;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final medal = medalColor(rank);
    return Container(
      width: _badgeSize,
      height: _badgeSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: mine ? scheme.primary : scheme.surfaceContainerHigh,
        border: medal == null ? null : Border.all(color: medal, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Gap.xs),
        child: FittedBox(
          child: Text(
            context.n(rank),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: mine ? scheme.onPrimary : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Someone else's row: rank and score only.
class _Rung extends StatelessWidget {
  const _Rung({required this.rank, required this.score, required this.seed});

  final int rank;
  final double score;

  /// Varies the blurred shapes so rows don't look identical.
  final int seed;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final points = l.dailyExamPoints(_score(context, score));
    return Semantics(
      container: true,
      label: '${l.dailyExamRankSemantics(context.n(rank))}, $points, ${l.dailyExamIdentityHidden}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.xs + 2),
        child: Row(
          children: [
            _RankBadge(rank: rank),
            Gap.w12,
            Expanded(child: _HiddenIdentity(seed: seed + rank)),
            Gap.w8,
            Text(
              points,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// My own row: crisp, highlighted, with my avatar and time.
class _MyRung extends StatelessWidget {
  const _MyRung({required this.me, this.name, this.avatarUrl});

  final MyStanding me;
  final String? name;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final points = l.dailyExamPoints(_score(context, me.score));
    final time = _time(context, me.timeTakenSeconds);
    final name = this.name;
    return Semantics(
      container: true,
      label: '${l.dailyExamYou}, ${l.dailyExamRankSemantics(context.n(me.rank))}, $points',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.xs),
        child: Material(
          color: scheme.primaryContainer,
          elevation: 2,
          shadowColor: scheme.primary.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: Radii.button,
            side: BorderSide(color: scheme.primary, width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.sm + 2),
            child: Row(
              children: [
                _RankBadge(rank: me.rank, mine: true),
                Gap.w12,
                UserAvatar(name: name, url: avatarUrl, radius: 16),
                Gap.w8,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.dailyExamYou,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      if (name != null && name.isNotEmpty)
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                          ),
                        ),
                    ],
                  ),
                ),
                Gap.w8,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      points,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (time != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.timer_outlined, size: 13, color: scheme.onPrimaryContainer),
                          const SizedBox(width: Gap.xxs),
                          Text(time, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onPrimaryContainer)),
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

/// "⋮" between rungs that aren't adjacent.
class _LadderGap extends StatelessWidget {
  const _LadderGap();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: Gap.sm),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Container(
            width: _badgeSize,
            height: 24,
            alignment: Alignment.center,
            // Card-coloured so the rail breaks around the dots.
            color: scheme.surface,
            child: Icon(Icons.more_vert_rounded, size: 18, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// An avatar and a name, blurred beyond recognition (they are not even
/// real: no identity ever reaches the app).
class _HiddenIdentity extends StatelessWidget {
  const _HiddenIdentity({required this.seed});

  final int seed;

  static const _tints = [
    Color(0xFF0E7C66),
    Color(0xFF3559E0),
    Color(0xFF7A4BD6),
    Color(0xFFD9480F),
    Color(0xFFC2255C),
    Color(0xFF2B8A3E),
  ];

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    final name = 64.0 + (seed * 37) % 56;
    final handle = 36.0 + (seed * 23) % 40;
    return ExcludeSemantics(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Row(
          children: [
            CircleAvatar(radius: 16, backgroundColor: _tints[seed % _tints.length].withValues(alpha: 0.75)),
            Gap.w12,
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: name,
                    height: 10,
                    decoration: BoxDecoration(
                      color: ink.withValues(alpha: 0.32),
                      borderRadius: const BorderRadius.all(Radius.circular(5)),
                    ),
                  ),
                  Gap.h4,
                  Container(
                    width: handle,
                    height: 8,
                    decoration: BoxDecoration(
                      color: ink.withValues(alpha: 0.18),
                      borderRadius: const BorderRadius.all(Radius.circular(4)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The ladder before the exam: blurred placeholder rows under a lock.
class LockedLadder extends StatelessWidget {
  const LockedLadder({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.lg, Gap.sm, Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: Gap.sm),
              child: _LadderHeader(),
            ),
            Gap.h12,
            Stack(
              alignment: Alignment.center,
              children: [
                ExcludeSemantics(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                    child: Column(
                      children: [
                        for (var i = 0; i < 5; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.xs + 2),
                            child: Row(
                              children: [
                                Container(
                                  width: _badgeSize,
                                  height: _badgeSize,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: i == 2 ? scheme.primary : scheme.surfaceContainerHigh,
                                  ),
                                ),
                                Gap.w12,
                                Expanded(child: _HiddenIdentity(seed: i * 3 + 1)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: Gap.xl),
                  padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.92),
                    borderRadius: Radii.card,
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_rounded, color: scheme.primary),
                      Gap.h8,
                      Text(l.dailyExamLockedLadder, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
