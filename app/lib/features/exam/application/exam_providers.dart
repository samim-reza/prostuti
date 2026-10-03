import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/offline/offline_queue.dart';
import 'package:prostuti/core/pagination/paged_notifier.dart';
import 'package:prostuti/core/pagination/paged_state.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/exam/data/exam_repository.dart';

/// The user's unfinished exam ("resume" banner). The payload is cached on
/// device so opening the exam is instant.
final activeExamProvider = FutureProvider.autoDispose<ExamSession?>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(examRepositoryProvider).activeOrCached();
});

/// Latest few results for the compact strip on the Exams tab (cached first
/// page when offline).
final recentExamHistoryProvider = FutureProvider.autoDispose<List<ExamHistoryItem>>((ref) async {
  ref.watch(currentUserIdProvider);
  final page = await ref.watch(examRepositoryProvider).historyOrCached();
  return page.items.take(6).toList();
});

/// Submissions waiting in the offline queue; refreshes as the queue drains.
final pendingExamSubmissionsProvider = Provider.autoDispose<List<PendingExamSubmission>>((ref) {
  ref.watch(pendingSyncCountProvider);
  return ref.watch(examRepositoryProvider).pendingSubmissions();
});

final examResultProvider = FutureProvider.autoDispose.family<ExamResult, String>(
  (ref, sessionId) => ref.watch(examRepositoryProvider).resultCached(sessionId),
);

final examReviewProvider = FutureProvider.autoDispose.family<List<Question>, String>(
  (ref, sessionId) => ref.watch(examRepositoryProvider).reviewCached(sessionId),
);

/// Kind + config of a finished session (for "take it again").
final examSetupProvider = FutureProvider.autoDispose.family<ExamSetup, String>(
  (ref, sessionId) => ref.watch(examRepositoryProvider).setup(sessionId),
);

/// AI explanation per (question, UI language); kept for the app session once
/// it succeeds (each call may count against the free daily quota).
final aiExplanationProvider = FutureProvider.autoDispose.family<AiExplanation, (int, String)>((ref, key) async {
  final (questionId, locale) = key;
  final result = await ref.watch(examRepositoryProvider).explainDetailed(questionId, locale: locale);
  ref.keepAlive();
  return result;
});

/// Full exam history, keyset-paginated by `submitted_at`.
class ExamHistoryNotifier extends PagedNotifier<ExamHistoryItem, DateTime> {
  @override
  Future<PageResult<ExamHistoryItem, DateTime>> fetchPage(DateTime? cursor) =>
      ref.read(examRepositoryProvider).historyOrCached(before: cursor);

  @override
  List<ExamHistoryItem>? readCachedFirstPage() => ref.read(examRepositoryProvider).cachedHistory();

  @override
  Object idOf(ExamHistoryItem item) => item.sessionId;
}

final examHistoryProvider = NotifierProvider.autoDispose<ExamHistoryNotifier, PagedState<ExamHistoryItem, DateTime>>(
  ExamHistoryNotifier.new,
);
