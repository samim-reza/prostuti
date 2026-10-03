import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/offline/offline_queue.dart';
import 'package:prostuti/core/utils/bd_time.dart';
import 'package:prostuti/features/daily_notes/data/daily_note.dart';
import 'package:prostuti/features/daily_notes/data/daily_notes_repository.dart';

/// Today's notes + daily-exam summary, shared by the notes and daily-exam
/// screens (one cached request serves both).
class TodayNotesNotifier extends AsyncNotifier<TodayNotes> {
  DailyNotesRepository get _repo => ref.read(dailyNotesRepositoryProvider);

  String _userId() {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) throw const AuthFailure('not_authenticated');
    return uid;
  }

  @override
  Future<TodayNotes> build() {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) throw const AuthFailure('not_authenticated');
    return ref.watch(dailyNotesRepositoryProvider).today(userId: uid);
  }

  /// Pull-to-refresh / "day ended" refresh. Keeps showing the previous data
  /// while loading; returns the error (if any) so the UI can show a snack
  /// instead of replacing the content with an error page.
  Future<Object?> refresh() async {
    final previous = state.value;
    state = const AsyncLoading<TodayNotes>();
    try {
      final next = await _repo.today(userId: _userId(), force: true);
      if (ref.mounted) state = AsyncData(next);
      return null;
    } on Object catch (e, st) {
      if (!ref.mounted) return e;
      // Never keep showing a previous day's notes (they are "today only").
      final keep = previous != null && previous.noteDate == BdTime.todayIso();
      state = keep ? AsyncData(previous) : AsyncError<TodayNotes>(e, st);
      return e;
    }
  }

  /// After a successful download claim.
  void markDownloaded() {
    final current = state.value;
    if (current == null || current.downloaded) return;
    final next = current.copyWith(downloaded: true);
    state = AsyncData(next);
    final uid = ref.read(currentUserIdProvider);
    if (uid != null) unawaited(_repo.updateCached(uid, next));
  }
}

final todayNotesProvider = AsyncNotifierProvider.autoDispose<TodayNotesNotifier, TodayNotes>(TodayNotesNotifier.new);

/// Selected category filter on the notes screen (`null` = all).
class NoteCategoryFilter extends Notifier<NoteCategory?> {
  @override
  NoteCategory? build() => null;

  /// Selecting the active category again clears the filter.
  void select(NoteCategory? category) => state = (category == state) ? null : category;
}

final noteCategoryFilterProvider = NotifierProvider.autoDispose<NoteCategoryFilter, NoteCategory?>(
  NoteCategoryFilter.new,
);

/// Bookmark state of today's notes: ids (as strings, like
/// `bookmarks.item_id`) plus the ids whose change is still queued offline.
@immutable
class NoteBookmarks {
  const NoteBookmarks({this.ids = const {}, this.pending = const {}});

  final Set<String> ids;
  final Set<String> pending;

  bool contains(int noteId) => ids.contains('$noteId');
  bool isPending(int noteId) => pending.contains('$noteId');

  /// Overlays queued (not yet synced) toggles on the server/cached state.
  NoteBookmarks withPendingOps(Map<int, bool> ops) {
    final next = {...ids};
    ops.forEach((id, add) => add ? next.add('$id') : next.remove('$id'));
    return NoteBookmarks(ids: next, pending: {for (final id in ops.keys) '$id'});
  }
}

/// Today's bookmarks with optimistic, offline-queued toggling.
class NoteBookmarksNotifier extends AsyncNotifier<NoteBookmarks> {
  final _inFlight = <int>{};

  @override
  Future<NoteBookmarks> build() async {
    final uid = ref.watch(currentUserIdProvider);
    // Re-query only when the set of note ids changes, not on every refresh.
    final ids = await ref.watch(todayNotesProvider.selectAsync((t) => t.notes.map((n) => n.id).join(',')));
    if (uid == null || ids.isEmpty || !ref.mounted) return const NoteBookmarks();

    // Clear "pending sync" marks as the offline queue drains.
    final queue = OfflineQueue.instance.pendingCount;
    void onQueueChanged() {
      final current = state.value;
      if (current == null) return;
      final pending = DailyNotesRepository.pendingBookmarkOps();
      state = AsyncData(NoteBookmarks(ids: current.ids, pending: {for (final id in pending.keys) '$id'}));
    }

    queue.addListener(onQueueChanged);
    ref.onDispose(() => queue.removeListener(onQueueChanged));

    Set<String> saved;
    try {
      saved = await ref
          .read(dailyNotesRepositoryProvider)
          .bookmarkedNoteIds(userId: uid, isoDate: BdTime.todayIso(), noteIds: ids.split(',').map(int.parse).toList());
    } on Object {
      saved = <String>{}; // offline without cache: notes still render
    }
    return NoteBookmarks(ids: saved).withPendingOps(DailyNotesRepository.pendingBookmarkOps());
  }

  /// Returns the new bookmarked state and whether it was only queued
  /// (offline); throws after rolling back on a non-network failure.
  /// Ignores taps while the previous toggle of the same note is in flight.
  Future<({bool bookmarked, bool queued})?> toggle(DailyNote note) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) throw const AuthFailure('not_authenticated');
    if (!_inFlight.add(note.id)) return null;
    final repo = ref.read(dailyNotesRepositoryProvider);
    final before = state.value ?? const NoteBookmarks();
    final key = '${note.id}';
    final adding = !before.ids.contains(key);
    final optimistic = adding ? {...before.ids, key} : ({...before.ids}..remove(key));
    state = AsyncData(NoteBookmarks(ids: optimistic, pending: {...before.pending, key}));
    try {
      final done = await repo.setBookmark(userId: uid, note: note, bookmarked: adding);
      if (ref.mounted) {
        final now = state.value ?? const NoteBookmarks();
        state = AsyncData(NoteBookmarks(ids: now.ids, pending: done ? ({...now.pending}..remove(key)) : now.pending));
      }
      unawaited(repo.cacheBookmarkIds(uid, BdTime.todayIso(), optimistic));
      return (bookmarked: adding, queued: !done);
    } on Object {
      if (ref.mounted) {
        final now = state.value ?? const NoteBookmarks();
        state = AsyncData(
          NoteBookmarks(
            ids: adding ? ({...now.ids}..remove(key)) : {...now.ids, key},
            pending: {...now.pending}..remove(key),
          ),
        );
      }
      rethrow;
    } finally {
      _inFlight.remove(note.id);
    }
  }
}

final noteBookmarksProvider = AsyncNotifierProvider.autoDispose<NoteBookmarksNotifier, NoteBookmarks>(
  NoteBookmarksNotifier.new,
);
