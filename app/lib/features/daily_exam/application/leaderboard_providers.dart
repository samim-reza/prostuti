import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/features/daily_exam/data/daily_leaderboard.dart';
import 'package:prostuti/features/daily_exam/data/leaderboard_repository.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/exam/data/exam_repository.dart';

/// Which board to load: a Bangladesh date (`yyyy-MM-dd`) and how many rows.
typedef LeaderboardQuery = ({String date, int limit});

final dailyLeaderboardProvider = FutureProvider.autoDispose.family<DailyLeaderboard, LeaderboardQuery>((ref, q) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) throw const AuthFailure('not_authenticated');
  return ref.watch(leaderboardRepositoryProvider).fetch(userId: uid, isoDate: q.date, limit: q.limit);
});

/// Re-fetches one day's board bypassing the TTL (pull-to-refresh, after a
/// submission). Offline, the cached board is kept and served — never wiped.
Future<void> refreshLeaderboard(WidgetRef ref, LeaderboardQuery query) async {
  final uid = ref.read(currentUserIdProvider);
  if (uid == null) return;
  try {
    await ref
        .read(leaderboardRepositoryProvider)
        .fetch(userId: uid, isoDate: query.date, limit: query.limit, force: true);
  } on Object {
    // The provider below surfaces the error (or keeps showing cached data).
  }
  ref.invalidate(dailyLeaderboardProvider(query));
  try {
    await ref.read(dailyLeaderboardProvider(query).future);
  } on Object {
    // Rendered by the watching widget.
  }
}

/// The user's unfinished *daily* exam, if any (offers "resume"). Null when
/// unknown (e.g. offline) — starting then falls back to `start_exam`.
final activeDailySessionProvider = FutureProvider.autoDispose<ExamSession?>((ref) async {
  try {
    final session = await ref.watch(examRepositoryProvider).active();
    return session?.kind == ExamKind.daily ? session : null;
  } on Object {
    return null;
  }
});
