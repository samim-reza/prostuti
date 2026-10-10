import 'package:flutter/foundation.dart';
import 'package:prostuti/core/utils/json.dart';

/// The caller's own result (`get_daily_standing().me`); present only when
/// they submitted that day's exam.
@immutable
class MyStanding {
  const MyStanding({required this.rank, required this.score, this.timeTakenSeconds, this.percentile});

  factory MyStanding.fromJson(Map<String, dynamic> j) => MyStanding(
    rank: j.integer('rank'),
    score: j.dbl('score'),
    timeTakenSeconds: j.intOrNull('time_taken_seconds'),
    percentile: j.dblOrNull('percentile'),
  );

  final int rank;
  final double score;
  final int? timeTakenSeconds;

  /// "Top N %": share of participants ranked at or above me (0–100].
  final double? percentile;

  Map<String, dynamic> toJson() => {
    'rank': rank,
    'score': score,
    'time_taken_seconds': timeTakenSeconds,
    'percentile': percentile,
  };
}

/// An anonymous row next to mine on the ladder: just a rank and a score.
@immutable
class LadderRung {
  const LadderRung({required this.rank, required this.score});

  factory LadderRung.fromJson(Map<String, dynamic> j) => LadderRung(rank: j.integer('rank'), score: j.dbl('score'));

  final int rank;
  final double score;

  Map<String, dynamic> toJson() => {'rank': rank, 'score': score};
}

/// `get_daily_standing(p_date)`: my private place among all participants of
/// one day's exam. Carries no other user's identity.
@immutable
class DailyStanding {
  const DailyStanding({
    required this.date,
    required this.participants,
    this.totalMarks,
    this.topScore,
    this.me,
    this.neighbors = const [],
  });

  factory DailyStanding.fromJson(Map<String, dynamic> j) => DailyStanding(
    date: j.str('date'),
    participants: j.integer('participants'),
    totalMarks: j.intOrNull('total_marks'),
    topScore: j.dblOrNull('top_score'),
    me: j.objOrNull('me') == null ? null : MyStanding.fromJson(j.obj('me')),
    neighbors: j.list('neighbors', LadderRung.fromJson),
  );

  /// `yyyy-MM-dd` (Bangladesh day).
  final String date;
  final int participants;

  /// Questions (= full marks) of that day's exam; null when there was none.
  final int? totalMarks;

  /// The day's highest score; null without participants.
  final double? topScore;
  final MyStanding? me;

  /// Up to three rows above and three below mine, in ladder order.
  final List<LadderRung> neighbors;

  bool get attempted => me != null;

  /// Nobody took part (negative-cached).
  bool get isEmpty => participants == 0;

  /// A published exam existed that day.
  bool get hasExam => totalMarks != null || participants > 0;

  /// Rows ranked better than mine. Ties with me go below (same rank and
  /// score, so the order between them carries no information).
  List<LadderRung> get above {
    final me = this.me;
    if (me == null) return const [];
    return [
      for (final r in neighbors)
        if (r.rank < me.rank) r,
    ];
  }

  List<LadderRung> get below {
    final me = this.me;
    if (me == null) return const [];
    return [
      for (final r in neighbors)
        if (r.rank >= me.rank) r,
    ];
  }

  /// "Top N %" as a whole number, 1–100 (falls back to rank / participants).
  int? get topPercent {
    final me = this.me;
    if (me == null || participants <= 0) return null;
    final p = me.percentile ?? 100 * me.rank / participants;
    return p.ceil().clamp(1, 100);
  }

  /// The #1 row is not on the ladder yet (it is shown as an extra top rung).
  bool get topOutOfView {
    final me = this.me;
    if (me == null || me.rank == 1) return false;
    final above = this.above;
    return above.isEmpty || above.first.rank > 1;
  }

  /// Someone is ranked between the #1 rung and the ladder (draw a "⋮").
  bool get gapBelowTop {
    if (!topOutOfView) return false;
    final above = this.above;
    return above.isEmpty || above.first.rank > 2;
  }

  /// Participants are ranked below the last ladder row (draw a "⋮").
  bool get hasMoreBelow {
    final me = this.me;
    return me != null && participants > me.rank + below.length;
  }

  /// Marks between me and the next better score just above me, if any.
  ({int rank, double marks})? get gapToNext {
    final me = this.me;
    if (me == null) return null;
    final better = above.where((r) => r.score > me.score);
    if (better.isEmpty) return null;
    final next = better.last;
    return (rank: next.rank, marks: next.score - me.score);
  }

  Map<String, dynamic> toJson() => {
    'date': date,
    'participants': participants,
    'total_marks': totalMarks,
    'top_score': topScore,
    'me': me?.toJson(),
    'neighbors': neighbors.map((r) => r.toJson()).toList(),
  };
}
