import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/cache/cached_fetcher.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/network/rpc.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/pagination/paged_state.dart';
import 'package:prostuti/features/admin/data/admin_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pipeline stages accepted by `admin_run_pipeline`.
enum PipelineStage {
  ingestNews('ingest-news'),
  dailyNotes('generate-daily-notes'),
  dailyExam('generate-daily-exam'),
  notifications('dispatch-notifications');

  PipelineStage(this.wire);
  final String wire;
}

/// Staff-only operations. Everything here is live data (no cache): moderation
/// must act on the current state.
class AdminRepository {
  AdminRepository(this._client, this._cache);

  final SupabaseClient _client;
  final CachedFetcher _cache;

  static const questionPageSize = 20;
  static const reportPageSize = 30;

  /// Runs [body] and keeps the global connectivity state honest.
  Future<T> _live<T>(Future<T> Function() body) async {
    try {
      final result = await body();
      ConnectivityService.instance.reportSuccess();
      return result;
    } on Object catch (e) {
      final failure = AppFailure.from(e);
      if (failure is NetworkFailure) ConnectivityService.instance.reportFailure();
      throw failure;
    }
  }

  Future<AdminStats> dashboard() => _live(() async => AdminStats.fromJson(await _client.rpcMap('admin_dashboard')));

  Future<PageResult<AdminQuestion, int>> questions({required ReviewStatus review, int? subjectId, int? afterId}) =>
      _live(() async {
        final rows = await _client.rpcList(
          'admin_list_questions',
          params: {'p_review': review.name, 'p_subject': subjectId, 'p_limit': questionPageSize, 'p_after_id': afterId},
        );
        final items = rows.map(AdminQuestion.fromJson).toList(growable: false);
        return PageResult(items, items.length < questionPageSize ? null : items.last.id);
      });

  Future<void> updateQuestion(int id, Map<String, dynamic> patch) =>
      _live(() => _client.rpcCall<void>('admin_update_question', params: {'p_id': id, 'p_patch': patch}));

  Future<PageResult<AdminReport, DateTime>> reports({required String status, DateTime? before}) => _live(() async {
    final rows = await _client.rpcList(
      'admin_list_reports',
      params: {'p_status': status, 'p_limit': reportPageSize, 'p_before': before?.toUtc().toIso8601String()},
    );
    final items = rows.map(AdminReport.fromJson).toList(growable: false);
    return PageResult(items, items.length < reportPageSize ? null : items.last.createdAt);
  });

  /// [action]: `hide` | `restore` | `dismiss`.
  Future<void> resolveReport(int reportId, String action) =>
      _live(() => _client.rpcCall<void>('admin_resolve_report', params: {'p_report': reportId, 'p_action': action}));

  /// Returns the pg_net request id, or null when the Edge Function secrets
  /// are not configured on the server.
  Future<int?> runPipeline(PipelineStage stage) => _live(() async {
    final id = await _client.rpcCall<Object?>('admin_run_pipeline', params: {'p_stage': stage.wire});
    return id is num ? id.toInt() : int.tryParse('${id ?? ''}');
  });

  /// All schedules, including inactive ones (admins see them via RLS).
  Future<List<AdminSchedule>> schedules() => _live(() async {
    final rows = await guard(
      () => _client.from('exam_schedules').select(AdminSchedule.columns).order('expected_date').limit(200),
    );
    return rows.map(AdminSchedule.fromJson).toList(growable: false);
  });

  /// Inserts or updates; changing `expected_date` makes the database re-plan
  /// every study plan that targets this exam (trigger) and notify users.
  Future<AdminSchedule> saveSchedule(AdminSchedule s) => _live(() async {
    final row = s.isNew
        ? await guard(() => _client.from('exam_schedules').insert(s.toRow()).select(AdminSchedule.columns).single())
        : await guard(
            () =>
                _client.from('exam_schedules').update(s.toRow()).eq('id', s.id!).select(AdminSchedule.columns).single(),
          );
    // The learner-facing schedule list is cached for hours — drop it.
    await _cache.invalidate('exam_schedules');
    return AdminSchedule.fromJson(row);
  });
}

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AdminRepository(ref.watch(supabaseProvider), ref.watch(cachedFetcherProvider)),
);
