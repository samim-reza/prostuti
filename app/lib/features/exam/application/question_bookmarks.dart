import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/exam/data/question_actions_repository.dart';

@immutable
class QuestionBookmarkState {
  const QuestionBookmarkState({this.ids = const {}, this.checked = const {}});

  /// Bookmarked question ids (among the ones checked).
  final Set<int> ids;

  /// Ids whose bookmark status is known.
  final Set<int> checked;
}

/// Bookmark status of the questions on screen. Status is fetched in one
/// batched query per list (`ensureLoaded`), toggles are optimistic.
class QuestionBookmarks extends Notifier<QuestionBookmarkState> {
  @override
  QuestionBookmarkState build() {
    final userId = ref.watch(currentUserIdProvider); // reset on account switch
    _cacheKey = 'question_bookmark_ids:${userId ?? 'anon'}';
    // Last known bookmarks → correct icons offline (re-checked when online).
    final data = ref.read(cacheStoreProvider).read(_cacheKey)?.data;
    final known = data is List ? data.whereType<num>().map((e) => e.toInt()).toSet() : <int>{};
    return QuestionBookmarkState(ids: known);
  }

  late String _cacheKey;

  void _emit(QuestionBookmarkState value) {
    final changed = !setEquals(value.ids, state.ids);
    state = value;
    if (changed) {
      unawaited(ref.read(cacheStoreProvider).write(_cacheKey, value.ids.toList(), const Duration(days: 30)));
    }
  }

  QuestionActionsRepository get _repo => ref.read(questionActionsRepositoryProvider);

  /// Loads the status of [ids]; with [refresh] re-checks known ids too (the
  /// bookmarks screen may have removed some meanwhile).
  Future<void> ensureLoaded(Iterable<int> ids, {bool refresh = false}) async {
    final wanted = ids.where((id) => refresh || !state.checked.contains(id)).toSet();
    if (wanted.isEmpty) return;
    try {
      final found = await _repo.bookmarkedAmong(wanted);
      if (!ref.mounted) return;
      // Toggles still waiting in the offline queue win over the server.
      final pending = QuestionActionsRepository.pendingBookmarkOps();
      final ids = {...state.ids.difference(wanted), ...found};
      pending.forEach((id, add) => add ? ids.add(id) : ids.remove(id));
      _emit(QuestionBookmarkState(ids: ids, checked: {...state.checked, ...wanted}));
    } on Object catch (e) {
      debugPrint('bookmarks: status unavailable: $e');
    }
  }

  /// Flips the bookmark (optimistic; queued while offline). Returns the new
  /// status and whether it was only saved offline. Rolls back and rethrows
  /// on a server-side failure.
  Future<({bool bookmarked, bool queued})> toggle(Question question) async {
    final was = state.ids.contains(question.id);
    _set(question.id, bookmarked: !was);
    try {
      final delivered = await _repo.setBookmark(question, bookmarked: !was);
      return (bookmarked: !was, queued: !delivered);
    } on Object {
      if (ref.mounted) _set(question.id, bookmarked: was);
      rethrow;
    }
  }

  /// After an answer is revealed, refresh the saved payload so the bookmark
  /// carries the correct answer and explanation.
  Future<void> refreshPayload(Question question) async {
    if (!state.ids.contains(question.id)) return;
    try {
      await _repo.setBookmark(question, bookmarked: true);
    } on Object catch (e) {
      debugPrint('bookmarks: payload refresh failed: $e');
    }
  }

  void _set(int id, {required bool bookmarked}) {
    _emit(
      QuestionBookmarkState(
        ids: bookmarked ? {...state.ids, id} : ({...state.ids}..remove(id)),
        checked: {...state.checked, id},
      ),
    );
  }
}

final questionBookmarksProvider = NotifierProvider<QuestionBookmarks, QuestionBookmarkState>(QuestionBookmarks.new);

/// Fine-grained selector: a card rebuilds only when *its* status changes.
final isQuestionBookmarkedProvider = Provider.autoDispose.family<bool, int>(
  (ref, id) => ref.watch(questionBookmarksProvider.select((s) => s.ids.contains(id))),
);
