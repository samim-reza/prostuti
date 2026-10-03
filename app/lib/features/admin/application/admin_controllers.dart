import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/pagination/paged_notifier.dart';
import 'package:prostuti/core/pagination/paged_state.dart';
import 'package:prostuti/features/admin/data/admin_models.dart';
import 'package:prostuti/features/admin/data/admin_repository.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';

final adminDashboardProvider = FutureProvider.autoDispose<AdminStats>(
  (ref) => ref.watch(adminRepositoryProvider).dashboard(),
);

/// Review-queue filter (records compare by value → stable family keys).
typedef QuestionFilter = ({ReviewStatus review, int? subjectId});

class AdminQuestionsNotifier extends PagedNotifier<AdminQuestion, int> {
  AdminQuestionsNotifier(this.filter);

  final QuestionFilter filter;

  AdminRepository get _repo => ref.read(adminRepositoryProvider);

  @override
  Future<PageResult<AdminQuestion, int>> fetchPage(int? cursor) =>
      _repo.questions(review: filter.review, subjectId: filter.subjectId, afterId: cursor);

  @override
  Object idOf(AdminQuestion item) => item.id;

  /// Optimistically applies [patch]. Rows that no longer belong in this queue
  /// (verified in the "unverified" tab, rejected …) leave the list.
  Future<void> apply(AdminQuestion q, Map<String, dynamic> patch) async {
    if (patch.isEmpty) return;
    final before = state.items;
    final updated = q.applyPatch(patch);
    final stays = updated.status != 'rejected' && updated.reviewStatus == filter.review;
    if (stays) {
      replace(updated);
    } else {
      removeWhere((e) => e.id == q.id);
    }
    try {
      await _repo.updateQuestion(q.id, patch);
    } on Object {
      if (ref.mounted) state = state.copyWith(items: before);
      rethrow;
    }
  }
}

final adminQuestionsProvider = NotifierProvider.autoDispose
    .family<AdminQuestionsNotifier, PagedState<AdminQuestion, int>, QuestionFilter>(AdminQuestionsNotifier.new);

class AdminReportsNotifier extends PagedNotifier<AdminReport, DateTime> {
  AdminReportsNotifier(this.status);

  /// `open` | `actioned` | `dismissed`.
  final String status;

  @override
  Future<PageResult<AdminReport, DateTime>> fetchPage(DateTime? cursor) =>
      ref.read(adminRepositoryProvider).reports(status: status, before: cursor);

  @override
  Object idOf(AdminReport item) => item.id;

  /// Resolves every open report on the same target (that's what the RPC
  /// does), so they all leave the list together. `restore` only un-hides the
  /// content — the report keeps its status, so it stays listed.
  Future<void> resolve(AdminReport report, String action) async {
    final before = state.items;
    if (action != 'restore') removeWhere((r) => r.targetKey == report.targetKey);
    try {
      await ref.read(adminRepositoryProvider).resolveReport(report.id, action);
    } on Object {
      if (ref.mounted) state = state.copyWith(items: before);
      rethrow;
    }
  }
}

final adminReportsProvider = NotifierProvider.autoDispose
    .family<AdminReportsNotifier, PagedState<AdminReport, DateTime>, String>(AdminReportsNotifier.new);

class AdminSchedulesNotifier extends AsyncNotifier<List<AdminSchedule>> {
  @override
  Future<List<AdminSchedule>> build() => ref.read(adminRepositoryProvider).schedules();

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => ref.read(adminRepositoryProvider).schedules());
  }

  /// Saves and merges the server row back into the (date-sorted) list.
  Future<AdminSchedule> save(AdminSchedule schedule) async {
    final saved = await ref.read(adminRepositoryProvider).saveSchedule(schedule);
    final list = [
      for (final s in state.value ?? const <AdminSchedule>[])
        if (s.id != saved.id) s,
      saved,
    ]..sort((a, b) => a.expectedDate.compareTo(b.expectedDate));
    state = AsyncData(list);
    ref.invalidate(examSchedulesProvider);
    return saved;
  }
}

final adminSchedulesProvider = AsyncNotifierProvider.autoDispose<AdminSchedulesNotifier, List<AdminSchedule>>(
  AdminSchedulesNotifier.new,
);
