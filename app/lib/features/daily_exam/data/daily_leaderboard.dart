import 'package:flutter/foundation.dart';
import 'package:prostuti/core/utils/json.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';

/// The caller's own standing (`get_daily_leaderboard().me`); present only
/// when they submitted that day's exam.
@immutable
class MyStanding {
  const MyStanding({required this.rank, required this.score, this.timeTakenSeconds});

  factory MyStanding.fromJson(Map<String, dynamic> j) =>
      MyStanding(rank: j.integer('rank'), score: j.dbl('score'), timeTakenSeconds: j.intOrNull('time_taken_seconds'));

  final int rank;
  final double score;
  final int? timeTakenSeconds;

  Map<String, dynamic> toJson() => {'rank': rank, 'score': score, 'time_taken_seconds': timeTakenSeconds};
}

/// `get_daily_leaderboard(p_date, p_limit)` result.
@immutable
class DailyLeaderboard {
  const DailyLeaderboard({required this.date, required this.participants, this.entries = const [], this.me});

  factory DailyLeaderboard.fromJson(Map<String, dynamic> j) => DailyLeaderboard(
    date: j.str('date'),
    participants: j.integer('participants'),
    entries: j.list('entries', LeaderboardEntry.fromJson),
    me: j.objOrNull('me') == null ? null : MyStanding.fromJson(j.obj('me')),
  );

  /// `yyyy-MM-dd` (Bangladesh day).
  final String date;
  final int participants;

  /// Ordered by rank, then time taken (ties share a rank).
  final List<LeaderboardEntry> entries;
  final MyStanding? me;

  bool get isEmpty => entries.isEmpty;

  List<LeaderboardEntry> get podium => entries.take(3).toList(growable: false);

  List<LeaderboardEntry> get rest => entries.length <= 3 ? const [] : entries.sublist(3);

  Map<String, dynamic> toJson() => {
    'date': date,
    'participants': participants,
    'entries': entries.map(leaderboardEntryToJson).toList(),
    'me': me?.toJson(),
  };
}

Map<String, dynamic> leaderboardEntryToJson(LeaderboardEntry e) => {
  'rank': e.rank,
  'user_id': e.userId,
  'username': e.username,
  'full_name': e.fullName,
  'avatar_url': e.avatarUrl,
  'score': e.score,
  'time_taken_seconds': e.timeTakenSeconds,
};

/// "Pin my rank": the caller's standing when it should be pinned below the
/// list — i.e. they have a result but their row is not among [visible]
/// (outside the top N that was fetched or shown). Null otherwise.
MyStanding? pinnedStanding(DailyLeaderboard board, String? myUserId, {Iterable<LeaderboardEntry>? visible}) {
  final me = board.me;
  if (me == null) return null;
  final rows = visible ?? board.entries;
  if (myUserId != null) {
    return rows.any((e) => e.userId == myUserId) ? null : me;
  }
  // Without a user id, fall back to rank/score/time matching.
  final shown = rows.any((e) => e.rank == me.rank && e.score == me.score && e.timeTakenSeconds == me.timeTakenSeconds);
  return shown ? null : me;
}
