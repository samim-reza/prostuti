import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/cache/cached_fetcher.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/network/rpc.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/offline/offline_queue.dart';
import 'package:prostuti/core/utils/bd_time.dart';
import 'package:prostuti/core/utils/json.dart';
import 'package:prostuti/features/daily_notes/application/current_affairs_failures.dart';
import 'package:prostuti/features/daily_notes/data/daily_note.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// How the PDF download was earned (`claim_note_download(p_method)`).
enum DownloadMethod {
  /// Watched a rewarded ad.
  ad,

  /// Has the ad-free add-on.
  addon,
}

/// Cache policy for today's notes: fresh until the Bangladesh day ends (at
/// least one minute), while "not published yet" answers are re-checked
/// every 10 minutes (negative caching) so they appear soon after 6 AM.
CachePolicy todayNotesPolicy(Duration untilEndOfDay) {
  const minTtl = Duration(minutes: 1);
  const emptyTtl = Duration(minutes: 10);
  final ttl = untilEndOfDay < minTtl ? minTtl : untilEndOfDay;
  return CachePolicy(ttl: ttl, negativeTtl: ttl < emptyTtl ? ttl : emptyTtl);
}

/// Daily current-affairs notes: today's payload, PDF download claims and
/// note bookmarks.
class DailyNotesRepository {
  DailyNotesRepository(this._client, this._fetcher);

  final SupabaseClient _client;
  final CachedFetcher _fetcher;

  /// Per user (download state) and per Bangladesh day (notes are day-only).
  static String cacheKey(String userId, String isoDate) => 'today_notes:$userId:$isoDate';

  Future<TodayNotes> today({required String userId, bool force = false}) {
    return _fetcher.get<TodayNotes>(
      cacheKey(userId, BdTime.todayIso()),
      fetch: () async => TodayNotes.fromJson(await _client.rpcMap('get_today_notes')),
      encode: (v) => v.toJson(),
      decode: (j) => TodayNotes.fromJson(Map<String, dynamic>.from(j! as Map)),
      policy: todayNotesPolicy(BdTime.untilEndOfToday()),
      isEmpty: (v) => v.isIncomplete,
      forceRefresh: force,
    );
  }

  /// Writes an updated copy (e.g. `downloaded: true`) back to the cache,
  /// keeping the remaining TTL semantics.
  Future<void> updateCached(String userId, TodayNotes value) async {
    final policy = todayNotesPolicy(BdTime.untilEndOfToday());
    await _fetcher.store.write(
      cacheKey(userId, value.noteDate),
      value.toJson(),
      value.isIncomplete ? policy.negativeTtl : policy.ttl,
    );
  }

  Future<void> invalidateToday(String userId) => _fetcher.invalidate(cacheKey(userId, BdTime.todayIso()));

  /// Records today's download. Throws `feature_locked` for `addon` without
  /// the ad-free add-on, `no_notes_today` when nothing is published.
  Future<void> claimDownload(DownloadMethod method) async {
    await _client.rpcMap('claim_note_download', params: {'p_method': method.name});
  }

  static String bookmarksKey(String userId, String isoDate) => 'note_bookmarks:$userId:$isoDate';

  static const _bookmarksPolicy = CachePolicy(ttl: Duration(minutes: 10), negativeTtl: Duration(minutes: 10));

  /// Which of [noteIds] the user has bookmarked (RLS limits rows to the
  /// owner). Cached per day so bookmark state renders offline.
  Future<Set<String>> bookmarkedNoteIds({
    required String userId,
    required String isoDate,
    required List<int> noteIds,
    bool force = false,
  }) async {
    if (noteIds.isEmpty) return <String>{};
    final ids = await _fetcher.get<List<String>>(
      bookmarksKey(userId, isoDate),
      fetch: () async {
        final rows = await guard(
          () => _client
              .from('bookmarks')
              .select('item_id')
              .eq('item_type', 'note')
              .inFilter('item_id', noteIds.map((id) => '$id').toList()),
        );
        return [for (final r in rows) r['item_id'].toString()];
      },
      encode: (v) => v,
      decode: (j) => (j! as List).map((e) => e.toString()).toList(),
      policy: _bookmarksPolicy,
      forceRefresh: force,
    );
    return ids.toSet();
  }

  /// Write-through after an optimistic toggle (keeps offline state right).
  Future<void> cacheBookmarkIds(String userId, String isoDate, Set<String> ids) =>
      _fetcher.store.write(bookmarksKey(userId, isoDate), ids.toList(), _bookmarksPolicy.ttl);

  /// Offline-queue operation type for bookmark toggles.
  static const bookmarkOp = 'daily_notes.bookmark';

  /// Adds/removes a note bookmark now, or queues it while offline. Both
  /// directions are idempotent (primary key user+type+item), so replays are
  /// safe. Returns true when it already reached the server.
  Future<bool> setBookmark({required String userId, required DailyNote note, required bool bookmarked}) {
    return OfflineQueue.instance.run(bookmarkOp, {
      'user_id': userId,
      'note_id': note.id,
      'add': bookmarked,
      'note': note.toJson(),
    });
  }

  /// Executes a queued [bookmarkOp].
  Future<void> applyBookmarkOp(Map<String, dynamic> payload) async {
    final userId = payload.str('user_id');
    if (payload.boolean('add')) {
      await addBookmark(userId: userId, note: DailyNote.fromJson(payload.obj('note')));
    } else {
      await removeBookmark(userId: userId, noteId: payload.integer('note_id'));
    }
  }

  /// Stores the whole note (both languages) as the payload so it stays
  /// readable after today, when RLS hides the row.
  Future<void> addBookmark({required String userId, required DailyNote note}) async {
    try {
      await guard(
        () => _client.from('bookmarks').insert({
          'user_id': userId,
          'item_type': 'note',
          'item_id': '${note.id}',
          'payload': note.toJson(),
        }),
      );
    } on ConflictFailure {
      // Already bookmarked (e.g. from another device) — that's the goal.
    }
  }

  Future<void> removeBookmark({required String userId, required int noteId}) => guard(
    () => _client.from('bookmarks').delete().eq('user_id', userId).eq('item_type', 'note').eq('item_id', '$noteId'),
  );

  /// Note ids whose bookmark toggle is still waiting in the offline queue,
  /// with the final desired state (last op wins, FIFO).
  static Map<int, bool> pendingBookmarkOps() {
    final result = <int, bool>{};
    for (final op in OfflineQueue.instance.pendingOf(bookmarkOp)) {
      result[op.payload.integer('note_id')] = op.payload.boolean('add');
    }
    return result;
  }
}

final dailyNotesRepositoryProvider = Provider<DailyNotesRepository>((ref) {
  final repo = DailyNotesRepository(ref.watch(supabaseProvider), ref.watch(cachedFetcherProvider));
  OfflineQueue.instance.register(DailyNotesRepository.bookmarkOp, repo.applyBookmarkOp);
  registerCurrentAffairsMessages();
  return repo;
});
