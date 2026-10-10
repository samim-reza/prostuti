import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/features/daily_exam/data/daily_standing.dart';
import 'package:prostuti/features/daily_exam/data/leaderboard_repository.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/exam/data/exam_repository.dart';

/// My standing in one day's exam, keyed by Bangladesh date (`yyyy-MM-dd`).
/// Backs the leaderboard screen and the daily-exam page; the exam screen
/// invalidates it after a daily exam is submitted.
final dailyLeaderboardProvider = FutureProvider.autoDispose.family<DailyStanding, String>((ref, isoDate) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) throw const AuthFailure('not_authenticated');
  return ref.watch(leaderboardRepositoryProvider).fetch(userId: uid, isoDate: isoDate);
});

/// Re-fetches one day's standing bypassing the TTL (pull-to-refresh, after a
/// submission). Offline, the cached standing is kept and served — never wiped.
Future<void> refreshLeaderboard(WidgetRef ref, String isoDate) async {
  final uid = ref.read(currentUserIdProvider);
  if (uid == null) return;
  try {
    await ref.read(leaderboardRepositoryProvider).fetch(userId: uid, isoDate: isoDate, force: true);
  } on Object {
    // The provider below surfaces the error (or keeps showing cached data).
  }
  ref.invalidate(dailyLeaderboardProvider(isoDate));
  try {
    await ref.read(dailyLeaderboardProvider(isoDate).future);
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
