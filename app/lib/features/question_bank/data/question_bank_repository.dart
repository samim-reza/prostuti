import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/cache/cached_fetcher.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/network/rpc.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/offline/offline_queue.dart';
import 'package:prostuti/features/exam/application/exam_failure_messages.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/question_bank/data/offline_pack_store.dart';
import 'package:prostuti/features/question_bank/data/question_bank_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One page of wrong answers plus the keyset cursor of the *raw* page.
class WrongAnswerPage {
  const WrongAnswerPage(this.items, this.nextCursor);
  final List<WrongAnswer> items;
  final DateTime? nextCursor;
}

/// Question-bank RPCs: practice browsing (keyset by id), answering,
/// revealing, the wrong-answer notebook and question sources.
class QuestionBankRepository {
  QuestionBankRepository(this._client, this._cache);

  final SupabaseClient _client;
  final CachedFetcher _cache;

  static const practicePageSize = 20;
  static const offlinePackPageSize = 300;

  /// Offline-queue operation type for answers given in pack mode.
  static const syncOp = 'practice.sync';

  String get _uid => _client.auth.currentUser?.id ?? 'anon';

  /// Published questions ordered by id, after [afterId] (keyset pagination).
  Future<List<Question>> practiceQuestions({
    int? subjectId,
    int? topicId,
    int? sourceId,
    String? track,
    int? afterId,
    bool unseenOnly = false,
    String? search,
    int limit = practicePageSize,
  }) async {
    final rows = await _client.rpcList(
      'get_practice_questions',
      params: {
        'p_subject': subjectId,
        'p_topic': topicId,
        'p_source': sourceId,
        'p_limit': limit,
        'p_after_id': afterId,
        'p_unseen_only': unseenOnly,
        'p_search': (search == null || search.trim().isEmpty) ? null : search.trim(),
        'p_track': ?track,
      },
    );
    return rows.map(Question.fromJson).toList(growable: false);
  }

  Future<PracticeVerdict> answer(int questionId, int selected) async {
    final json = await _client.rpcMap(
      'answer_practice_question',
      params: {'p_question': questionId, 'p_selected': selected},
    );
    return PracticeVerdict.fromJson(json);
  }

  Future<PracticeVerdict> reveal(int questionId) async {
    final json = await _client.rpcMap('reveal_answer', params: {'p_question': questionId});
    return PracticeVerdict.fromJson(json);
  }

  /// Wrong-answer notebook, newest first, keyset by `attempted_at`.
  ///
  /// `get_wrong_answers` applies `p_subject` *after* its LIMIT, so a filtered
  /// page can come back short or empty while older matches exist. We
  /// therefore page through the unfiltered list and filter on the client,
  /// fetching up to [maxRounds] raw pages to fill one screen.
  Future<WrongAnswerPage> wrongAnswers({DateTime? before, int? subjectId, int limit = 30, int maxRounds = 4}) async {
    final out = <WrongAnswer>[];
    var cursor = before;
    for (var round = 0; round < maxRounds; round++) {
      final rows = await _client.rpcList(
        'get_wrong_answers',
        params: {'p_limit': limit, 'p_before': cursor?.toUtc().toIso8601String(), 'p_subject': null},
      );
      final page = rows.map(WrongAnswer.fromJson).toList();
      cursor = page.length < limit ? null : page.last.attemptedAt;
      out.addAll(subjectId == null ? page : page.where((w) => w.question.subjectId == subjectId));
      if (cursor == null || out.isNotEmpty) break;
    }
    return WrongAnswerPage(out, cursor);
  }

  /// First wrong-answer page saved on device (instant paint / offline).
  List<WrongAnswer>? cachedWrongAnswers(int? subjectId) {
    final data = _cache.store.read('wrong_answers:$_uid:${subjectId ?? 'all'}')?.data;
    if (data is! List) return null;
    return data
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => WrongAnswer.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> cacheWrongAnswers(int? subjectId, List<WrongAnswer> items) => _cache.store.write(
    'wrong_answers:$_uid:${subjectId ?? 'all'}',
    items.take(30).map((e) => e.toJson()).toList(),
    const Duration(days: 30),
  );

  /// [wrongAnswers] with the cached first page as the offline fallback.
  Future<WrongAnswerPage> wrongAnswersOrCached({DateTime? before, int? subjectId}) async {
    if (before == null && !ConnectivityService.instance.isOnline) {
      final cached = cachedWrongAnswers(subjectId);
      if (cached != null) return WrongAnswerPage(cached, null);
    }
    try {
      final page = await wrongAnswers(before: before, subjectId: subjectId);
      if (before == null) await cacheWrongAnswers(subjectId, page.items);
      return page;
    } on NetworkFailure {
      ConnectivityService.instance.reportFailure();
      final cached = before == null ? cachedWrongAnswers(subjectId) : null;
      if (cached == null) rethrow;
      return WrongAnswerPage(cached, null);
    }
  }

  /// One page of a subject's offline pack (questions **with** answers).
  Future<List<Question>> offlinePackPage(int subjectId, {int? afterId}) async {
    final rows = await _client.rpcList(
      'get_offline_pack',
      params: {'p_subject': subjectId, 'p_limit': offlinePackPageSize, 'p_after_id': afterId},
    );
    return rows.map(Question.fromJson).toList(growable: false);
  }

  /// Every question of [subjectId] for offline practice, paged by id.
  Future<List<Question>> downloadOfflinePack(int subjectId, {void Function(int fetched)? onProgress}) async {
    final all = <Question>[];
    int? after;
    for (var round = 0; round < 20; round++) {
      final page = await offlinePackPage(subjectId, afterId: after);
      all.addAll(page);
      onProgress?.call(all.length);
      if (page.length < offlinePackPageSize) break;
      after = page.last.id;
    }
    return all;
  }

  /// Uploads answers given offline (idempotent by `client_id`).
  Future<void> syncAttempts(List<PracticeAttempt> attempts) => _client.rpcCall<dynamic>(
    'sync_practice_attempts',
    params: {'p_attempts': attempts.map((a) => a.toJson()).toList()},
  );

  /// Executes a queued [syncOp].
  Future<void> applySyncOp(Map<String, dynamic> payload) async {
    final attempts = (payload['attempts'] as List? ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => PracticeAttempt.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    if (attempts.isNotEmpty) await syncAttempts(attempts);
  }

  /// Sources with published questions (`p_kind` null → all kinds).
  Future<List<QuestionSource>> sources({SourceKind? kind, bool force = false}) {
    return _cache.get<List<QuestionSource>>(
      'question_sources:${kind?.wire ?? 'all'}',
      forceRefresh: force,
      fetch: () async {
        final rows = await _client.rpcList('get_question_sources', params: {'p_kind': kind?.wire});
        return rows.map(QuestionSource.fromJson).toList();
      },
      encode: (v) => v.map((s) => s.toJson()).toList(),
      decode: (j) => (j! as List).map((e) => QuestionSource.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      policy: const CachePolicy(ttl: Duration(hours: 6), negativeTtl: Duration(minutes: 20)),
      isEmpty: (v) => v.isEmpty,
    );
  }
}

final questionBankRepositoryProvider = Provider<QuestionBankRepository>((ref) {
  registerExamFailureMessages();
  final repo = QuestionBankRepository(ref.watch(supabaseProvider), ref.watch(cachedFetcherProvider));
  OfflineQueue.instance.register(QuestionBankRepository.syncOp, repo.applySyncOp);
  return repo;
});

/// The dedicated Hive box holding offline packs (opened once).
final packStorageProvider = FutureProvider<PackStorage>((ref) async => HivePackStorage.open());

/// Offline packs of the signed-in user.
final offlinePackStoreProvider = FutureProvider<OfflinePackStore>((ref) async {
  final userId = ref.watch(currentUserIdProvider) ?? 'anon';
  final storage = await ref.watch(packStorageProvider.future);
  return OfflinePackStore(storage, userId);
});
