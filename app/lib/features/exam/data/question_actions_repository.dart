import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/network/rpc.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/offline/offline_queue.dart';
import 'package:prostuti/core/utils/json.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Per-question actions shared by exam review, practice and the wrong-answer
/// notebook: bookmarks (`bookmarks` table, item_type `question`) and
/// "wrong answer" reports (`reports` table). Both work offline through the
/// [OfflineQueue] (upsert/delete and the unique report key make replays safe).
class QuestionActionsRepository {
  QuestionActionsRepository(this._client);

  final SupabaseClient _client;

  static const bookmarkOp = 'question.bookmark';
  static const reportOp = 'question.report';

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthFailure('not_authenticated');
    return id;
  }

  /// Which of [ids] the user has bookmarked (one query per batch).
  Future<Set<int>> bookmarkedAmong(Iterable<int> ids) async {
    final keys = ids.map((e) => '$e').toSet().toList();
    if (keys.isEmpty) return {};
    final rows = await guard(
      () => _client.from('bookmarks').select('item_id').eq('item_type', 'question').inFilter('item_id', keys),
    );
    return rows.map((r) => int.tryParse('${r['item_id']}')).whereType<int>().toSet();
  }

  /// Saves the question with whatever answer details are known, so the
  /// bookmarks screen can show it offline without another round trip.
  Future<void> bookmark(Question question) => guard(
    () => _client.from('bookmarks').upsert({
      'user_id': _uid,
      'item_type': 'question',
      'item_id': '${question.id}',
      'payload': question.toJson(),
    }),
  );

  Future<void> removeBookmark(int questionId) => guard(
    () =>
        _client.from('bookmarks').delete().eq('user_id', _uid).eq('item_type', 'question').eq('item_id', '$questionId'),
  );

  /// Reports a wrong answer key. Duplicate reports → [ConflictFailure].
  Future<void> reportWrongAnswer(int questionId, {String? details, String? userId}) => guard(
    () => _client.from('reports').insert({
      'reporter_id': userId ?? _uid,
      'target_type': 'question',
      'target_id': '$questionId',
      'reason': 'wrong_answer',
      if (details != null && details.trim().isNotEmpty) 'details': details.trim(),
    }),
  );

  /// Adds/removes a bookmark now, or queues it while offline. Returns true
  /// when it already reached the server.
  Future<bool> setBookmark(Question question, {required bool bookmarked}) =>
      OfflineQueue.instance.run(bookmarkOp, {'user_id': _uid, 'question': question.toJson(), 'add': bookmarked});

  /// Executes a queued [bookmarkOp].
  Future<void> applyBookmarkOp(Map<String, dynamic> payload) async {
    final question = Question.fromJson(payload.obj('question'));
    final userId = payload.str('user_id');
    if (payload.boolean('add')) {
      await guard(
        () => _client.from('bookmarks').upsert({
          'user_id': userId,
          'item_type': 'question',
          'item_id': '${question.id}',
          'payload': question.toJson(),
        }),
      );
    } else {
      await guard(
        () => _client
            .from('bookmarks')
            .delete()
            .eq('user_id', userId)
            .eq('item_type', 'question')
            .eq('item_id', '${question.id}'),
      );
    }
  }

  /// Bookmark toggles still waiting in the queue: question id → final state.
  static Map<int, bool> pendingBookmarkOps() {
    final result = <int, bool>{};
    for (final op in OfflineQueue.instance.pendingOf(bookmarkOp)) {
      result[op.payload.obj('question').integer('id')] = op.payload.boolean('add');
    }
    return result;
  }

  /// Sends (or queues) a wrong-answer report. Returns true when delivered.
  Future<bool> report(int questionId, {String? details}) =>
      OfflineQueue.instance.run(reportOp, {'user_id': _uid, 'question_id': questionId, 'details': details});

  /// Executes a queued [reportOp]; a duplicate report is already the goal.
  Future<void> applyReportOp(Map<String, dynamic> payload) async {
    try {
      await reportWrongAnswer(
        payload.integer('question_id'),
        details: payload.strOrNull('details'),
        userId: payload.strOrNull('user_id'),
      );
    } on ConflictFailure {
      // Reported before (maybe from another device).
    }
  }
}

final questionActionsRepositoryProvider = Provider<QuestionActionsRepository>((ref) {
  final repo = QuestionActionsRepository(ref.watch(supabaseProvider));
  OfflineQueue.instance
    ..register(QuestionActionsRepository.bookmarkOp, repo.applyBookmarkOp)
    ..register(QuestionActionsRepository.reportOp, repo.applyReportOp);
  return repo;
});
