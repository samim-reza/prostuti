import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/cache/cache_store.dart';
import 'package:prostuti/core/cache/cached_fetcher.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/network/rpc.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/offline/offline_queue.dart';
import 'package:prostuti/core/pagination/paged_state.dart';
import 'package:prostuti/core/utils/json.dart';
import 'package:prostuti/features/exam/application/exam_failure_messages.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Outcome of [ExamRepository.submitOrQueue]: the result, or `null` when
/// the submission waits in the offline queue.
@immutable
class ExamSubmitOutcome {
  const ExamSubmitOutcome(this.result);
  final ExamResult? result;
  bool get isQueued => result == null;
}

/// A submission waiting in the offline queue (shown on the Exams tab).
@immutable
class PendingExamSubmission {
  const PendingExamSubmission({
    required this.sessionId,
    required this.title,
    required this.kind,
    required this.answered,
    required this.total,
    required this.queuedAt,
  });

  final String sessionId;
  final String title;
  final ExamKind kind;
  final int answered;
  final int total;
  final DateTime queuedAt;
}

/// Client for the server-side exam engine (`start_exam`, `submit_exam`…).
///
/// Offline-first:
/// * the session payload, answers and flags live on device, so an exam in
///   progress is fully answerable without internet and survives the app
///   being killed;
/// * submissions go through [OfflineQueue] (`submit_exam` is idempotent);
/// * results, reviews, history and the active exam are cached for offline
///   viewing.
class ExamRepository {
  ExamRepository(this._client, this._store) : _fetcher = CachedFetcher(_store);

  final SupabaseClient _client;
  final CacheStore _store;
  final CachedFetcher _fetcher;

  /// Offline-queue operation type for exam submissions.
  static const submitOp = 'exam.submit';

  static String _answersKey(String sessionId) => 'exam_answers:$sessionId';
  static String _flagsKey(String sessionId) => 'exam_flags:$sessionId';
  static String _sessionKey(String sessionId) => 'exam_session:$sessionId';
  static String _resultKey(String sessionId) => 'exam_result:$sessionId';
  static String _reviewKey(String sessionId) => 'exam_review:$sessionId';
  String get _uid => _client.auth.currentUser?.id ?? 'anon';
  String get _activeKey => 'exam_active:$_uid';
  String get _historyKey => 'exam_history:$_uid';

  static const _resultPolicy = CachePolicy(ttl: Duration(minutes: 10));
  static const _reviewPolicy = CachePolicy(ttl: Duration(days: 30), negativeTtl: Duration(minutes: 1));

  /// Starts an exam and keeps the payload on device until the deadline
  /// (+1 h grace), so `ExamSessionScreen` opens instantly via [loadSession].
  Future<ExamSession> start(ExamKind kind, {Map<String, dynamic> config = const {}}) async {
    final json = await _client.rpcMap('start_exam', params: {'p_kind': kind.wire, 'p_config': config});
    final session = ExamSession.fromJson(json);
    await cacheSession(session);
    return session;
  }

  /// Persists [session] as `exam_session:<id>` (TTL: until deadline + 1 h)
  /// and remembers it as the user's active exam (offline "resume").
  Future<void> cacheSession(ExamSession session) async {
    var ttl = session.deadlineAt.difference(DateTime.now());
    if (ttl.isNegative) ttl = Duration.zero;
    ttl += const Duration(hours: 1);
    await Future.wait([
      _store.write(_sessionKey(session.sessionId), session.toJson(), ttl),
      _store.write(_activeKey, session.sessionId, ttl),
    ]);
  }

  /// The locally cached session payload, if still within its TTL.
  ExamSession? cachedSession(String sessionId) {
    final entry = _store.read(_sessionKey(sessionId));
    final data = entry?.data;
    if (entry == null || !entry.isFresh || data is! Map) return null;
    try {
      return ExamSession.fromJson(Map<String, dynamic>.from(data));
    } on Object {
      return null;
    }
  }

  /// Session for the exam screen: device cache → the server's active exam
  /// (when the ids match) → [NotFoundFailure].
  Future<ExamSession> loadSession(String sessionId) async {
    final cached = cachedSession(sessionId);
    if (cached != null) return cached;
    final current = await active();
    if (current != null && current.sessionId == sessionId) {
      await cacheSession(current);
      return current;
    }
    throw const NotFoundFailure('session_not_found');
  }

  /// How a session was started (kind + config), for "take it again".
  Future<ExamSetup> setup(String sessionId) async {
    final row = await guard(
      () => _client.from('exam_sessions').select('kind, config').eq('id', sessionId).maybeSingle(),
    );
    if (row == null) throw const NotFoundFailure('session_not_found');
    return ExamSetup.fromJson(row);
  }

  /// The user's unfinished exam (if any) — used to offer "resume".
  Future<ExamSession?> active() async {
    final json = await _client.rpcCall<dynamic>('get_active_exam');
    if (json == null) return null;
    return ExamSession.fromJson(Map<String, dynamic>.from(json as Map));
  }

  /// [active] with an offline fallback: the last started/resumed session
  /// kept on device, while its deadline hasn't passed and it isn't already
  /// waiting in the submit queue.
  Future<ExamSession?> activeOrCached() async {
    ExamSession? local() {
      final id = _store.read(_activeKey)?.data;
      if (id is! String || isSubmissionPending(id)) return null;
      final session = cachedSession(id);
      if (session == null || session.status != 'in_progress' || session.remaining == Duration.zero) return null;
      return session;
    }

    if (!ConnectivityService.instance.isOnline) return local();
    try {
      final session = await active();
      if (session != null) {
        await cacheSession(session);
      } else {
        await _store.invalidate(_activeKey);
      }
      ConnectivityService.instance.reportSuccess();
      return session;
    } on NetworkFailure {
      ConnectivityService.instance.reportFailure();
      return local();
    }
  }

  Map<int, int> savedAnswers(String sessionId) {
    final entry = _store.read(_answersKey(sessionId));
    if (entry?.data == null) return {};
    return Map<String, dynamic>.from(entry!.data! as Map).map((k, v) => MapEntry(int.parse(k), (v as num).toInt()));
  }

  Future<void> saveAnswers(String sessionId, Map<int, int> answers) =>
      _store.write(_answersKey(sessionId), answers.map((k, v) => MapEntry(k.toString(), v)), const Duration(days: 2));

  /// Questions the user marked "review later" (device only).
  Set<int> savedFlags(String sessionId) {
    final data = _store.read(_flagsKey(sessionId))?.data;
    if (data is! List) return {};
    return data.map((e) => e is num ? e.toInt() : int.tryParse('$e')).whereType<int>().toSet();
  }

  Future<void> saveFlags(String sessionId, Set<int> flags) =>
      _store.write(_flagsKey(sessionId), flags.toList(), const Duration(days: 2));

  Future<ExamResult> submit(String sessionId, Map<int, int> answers) async {
    final json = await _client.rpcMap(
      'submit_exam',
      params: {'p_session': sessionId, 'p_answers': answers.map((k, v) => MapEntry(k.toString(), v))},
    );
    await _afterSubmit(sessionId, json);
    return ExamResult.fromJson(json);
  }

  Future<void> _afterSubmit(String sessionId, Map<String, dynamic> resultJson) async {
    final active = _store.read(_activeKey)?.data;
    await Future.wait([
      _store.invalidate(_answersKey(sessionId)),
      _store.invalidate(_flagsKey(sessionId)),
      _store.invalidate(_sessionKey(sessionId)),
      if (active == sessionId) _store.invalidate(_activeKey),
      _store.write(_resultKey(sessionId), resultJson, _resultPolicy.ttl),
    ]);
  }

  /// Submits now when online, otherwise queues the submission; the queue
  /// replays it (idempotently) when connectivity returns.
  Future<ExamSubmitOutcome> submitOrQueue(ExamSession session, Map<int, int> answers) async {
    final id = session.sessionId;
    if (isSubmissionPending(id)) {
      unawaited(OfflineQueue.instance.flush());
      return const ExamSubmitOutcome(null);
    }
    final executed = await OfflineQueue.instance.run(submitOp, {
      'session_id': id,
      'answers': answers.map((k, v) => MapEntry(k.toString(), v)),
      'title': session.title,
      'kind': session.kind.wire,
      'total': session.total,
    }, id: id);
    if (!executed) {
      // Online but other writes were queued first: nudge the queue.
      if (ConnectivityService.instance.isOnline) unawaited(OfflineQueue.instance.flush());
      return const ExamSubmitOutcome(null);
    }
    return ExamSubmitOutcome(cachedResult(id) ?? await result(id));
  }

  /// Executes a queued [submitOp].
  Future<void> applySubmitOp(Map<String, dynamic> payload) async {
    final answers = <int, int>{};
    payload.obj('answers').forEach((k, v) {
      final q = int.tryParse(k);
      if (q != null && v is num) answers[q] = v.toInt();
    });
    await submit(payload.str('session_id'), answers);
  }

  /// Submissions still waiting for connectivity.
  List<PendingExamSubmission> pendingSubmissions() => [
    for (final op in OfflineQueue.instance.pendingOf(submitOp))
      PendingExamSubmission(
        sessionId: op.payload.str('session_id'),
        title: op.payload.str('title'),
        kind: ExamKind.parse(op.payload.strOrNull('kind')),
        answered: op.payload.obj('answers').length,
        total: op.payload.integer('total'),
        queuedAt: op.createdAt,
      ),
  ];

  bool isSubmissionPending(String sessionId) =>
      OfflineQueue.instance.pendingOf(submitOp).any((op) => op.payload.str('session_id') == sessionId);

  /// Result of an already submitted session (idempotent on the server).
  Future<ExamResult> result(String sessionId) async {
    final json = await _client.rpcMap('submit_exam', params: {'p_session': sessionId, 'p_answers': <String, int>{}});
    return ExamResult.fromJson(json);
  }

  /// The result stored on device by the last submit / result fetch.
  ExamResult? cachedResult(String sessionId) {
    final data = _store.read(_resultKey(sessionId))?.data;
    if (data is! Map) return null;
    return ExamResult.fromJson(Map<String, dynamic>.from(data));
  }

  /// Result for the result screen: cache-first when offline, refreshed
  /// online (the daily rank moves as others submit). Never calls
  /// `submit_exam` while this session's own submission is still queued —
  /// that would submit an empty answer sheet.
  Future<ExamResult> resultCached(String sessionId, {bool force = false}) async {
    if (isSubmissionPending(sessionId)) {
      await OfflineQueue.instance.flush();
      if (isSubmissionPending(sessionId)) {
        final cached = cachedResult(sessionId);
        if (cached != null) return cached;
        throw const NetworkFailure();
      }
    }
    final json = await _fetcher.get<Map<String, dynamic>>(
      _resultKey(sessionId),
      forceRefresh: force,
      fetch: () => _client.rpcMap('submit_exam', params: {'p_session': sessionId, 'p_answers': <String, int>{}}),
      encode: (v) => v,
      decode: (j) => Map<String, dynamic>.from(j! as Map),
      policy: _resultPolicy,
    );
    return ExamResult.fromJson(json);
  }

  Future<List<Question>> review(String sessionId) async {
    final rows = await _client.rpcList('get_exam_review', params: {'p_session': sessionId});
    return rows.map(Question.fromJson).toList();
  }

  /// Review (answers + explanations) — immutable after submission, so it is
  /// cached for a month and readable offline.
  Future<List<Question>> reviewCached(String sessionId) async {
    final rows = await _fetcher.get<List<Map<String, dynamic>>>(
      _reviewKey(sessionId),
      fetch: () => _client.rpcList('get_exam_review', params: {'p_session': sessionId}),
      encode: (v) => v,
      decode: (j) => (j! as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      policy: _reviewPolicy,
      isEmpty: (v) => v.isEmpty,
    );
    return rows.map(Question.fromJson).toList();
  }

  Future<PageResult<ExamHistoryItem, DateTime>> history({DateTime? before, int limit = 20}) async {
    final rows = await _client.rpcList(
      'get_exam_history',
      params: {'p_limit': limit, 'p_before': before?.toUtc().toIso8601String()},
    );
    final items = rows.map(ExamHistoryItem.fromJson).toList();
    return PageResult(items, items.length < limit ? null : items.last.submittedAt);
  }

  /// First history page saved on device (instant paint / offline).
  List<ExamHistoryItem>? cachedHistory() {
    final data = _store.read(_historyKey)?.data;
    if (data is! List) return null;
    return data
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => ExamHistoryItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> cacheHistory(List<ExamHistoryItem> items) =>
      _store.write(_historyKey, items.take(20).map((e) => e.toJson()).toList(), const Duration(days: 30));

  /// [history] with an offline fallback to the cached first page.
  Future<PageResult<ExamHistoryItem, DateTime>> historyOrCached({DateTime? before, int limit = 20}) async {
    if (before == null && !ConnectivityService.instance.isOnline) {
      final cached = cachedHistory();
      if (cached != null) return PageResult(cached.take(limit).toList(), null);
    }
    try {
      final page = await history(before: before, limit: limit);
      if (before == null) await cacheHistory(page.items);
      return page;
    } on NetworkFailure {
      ConnectivityService.instance.reportFailure();
      final cached = before == null ? cachedHistory() : null;
      if (cached == null) rethrow;
      return PageResult(cached.take(limit).toList(), null);
    }
  }

  Future<Leaderboard> dailyLeaderboard({String? isoDate, int limit = 50}) async {
    final json = await _client.rpcMap('get_daily_leaderboard', params: {'p_date': isoDate, 'p_limit': limit});
    return Leaderboard.fromJson(json);
  }

  /// AI explanation for a question (Edge Function, semantic-cached server side).
  /// [locale] is the UI language (`bn`/`en`) the explanation is written in.
  Future<String> explain(int questionId, {String locale = 'bn'}) async =>
      (await explainDetailed(questionId, locale: locale)).explanation;

  /// Explanation plus the optional memory tip returned by `ai-explain`.
  Future<AiExplanation> explainDetailed(int questionId, {String locale = 'bn'}) async {
    final res = await guard(
      () => _client.functions.invoke('ai-explain', body: {'question_id': questionId, 'locale': locale}),
    );
    final data = res.data;
    if (data is Map) {
      final parsed = AiExplanation.fromJson(Map<String, dynamic>.from(data));
      if (parsed.explanation.trim().isNotEmpty) return parsed;
    }
    throw const ServerFailure('empty_explanation');
  }

  Future<String> shareResult(String sessionId, {String? body}) =>
      _client.rpcCall<String>('share_exam_result', params: {'p_session': sessionId, 'p_body': body});
}

final examRepositoryProvider = Provider<ExamRepository>((ref) {
  // Exam errors (`no_questions`, `already_attempted` …) get localized
  // messages wherever they surface — including other features' screens.
  registerExamFailureMessages();
  final repo = ExamRepository(ref.watch(supabaseProvider), ref.watch(cacheStoreProvider));
  OfflineQueue.instance.register(ExamRepository.submitOp, repo.applySubmitOp);
  return repo;
});
