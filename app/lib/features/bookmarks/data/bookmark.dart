import 'package:flutter/foundation.dart';
import 'package:prostuti/core/offline/offline_queue.dart';
import 'package:prostuti/core/utils/json.dart';

/// `bookmarks.item_type`.
enum BookmarkType {
  question,
  note,
  post;

  static BookmarkType? parse(String? v) {
    for (final t in values) {
      if (t.name == v) return t;
    }
    return null;
  }
}

/// One row of `public.bookmarks`. The [payload] is a snapshot taken when the
/// item was saved, so bookmarks stay readable even when the original is no
/// longer visible (e.g. a daily note after its day ends).
@immutable
class Bookmark {
  const Bookmark({required this.type, required this.itemId, required this.payload, required this.createdAt});

  factory Bookmark.fromJson(Map<String, dynamic> j) => Bookmark(
    type: BookmarkType.parse(j.strOrNull('item_type')) ?? BookmarkType.question,
    itemId: j.str('item_id'),
    payload: j.obj('payload'),
    createdAt: j.dateOr('created_at', DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)),
  );

  static const columns = 'item_type, item_id, payload, created_at';

  final BookmarkType type;
  final String itemId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  /// Unique within one user's bookmarks (mirrors the primary key).
  String get key => bookmarkKey(type, itemId);

  Map<String, dynamic> toJson() => {
    'item_type': type.name,
    'item_id': itemId,
    'payload': payload,
    'created_at': createdAt.toUtc().toIso8601String(),
  };
}

String bookmarkKey(BookmarkType type, String itemId) => '${type.name}:$itemId';

/// Keyset cursor: (created_at, item_id) of the last row, newest first.
@immutable
class BookmarkCursor {
  const BookmarkCursor(this.createdAt, this.itemId);
  final DateTime createdAt;
  final String itemId;

  /// PostgREST `or` filter selecting rows strictly *after* this cursor in
  /// `created_at desc, item_id desc` order. Values are double-quoted so ':'
  /// and '.' inside timestamps/ids are never parsed as operators.
  String get orFilter {
    final ts = createdAt.toUtc().toIso8601String();
    final id = itemId.replaceAll('"', '');
    return 'created_at.lt."$ts",and(created_at.eq."$ts",item_id.lt."$id")';
  }
}

String? _firstStr(Map<String, dynamic> j, List<String> keys) {
  for (final k in keys) {
    final v = j[k];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  return null;
}

int? _firstInt(Map<String, dynamic> j, List<String> keys) {
  for (final k in keys) {
    final v = j.intOrNull(k);
    if (v != null) return v;
  }
  return null;
}

/// A saved question (payload = `Question.toJson()` from the exam feature, or
/// any compatible shape).
@immutable
class BookmarkedQuestion {
  const BookmarkedQuestion({
    required this.stem,
    required this.options,
    this.subjectId,
    this.correctIndex,
    this.selectedIndex,
    this.explanation,
    this.sourceRef,
    this.sourceUrl,
    this.year,
  });

  factory BookmarkedQuestion.fromPayload(Map<String, dynamic> p) {
    final options = p.strings('options');
    var correct = _firstInt(p, const ['correct_index', 'correctIndex', 'answer_index']);
    if (correct != null && (correct < 0 || correct >= options.length)) correct = null;
    return BookmarkedQuestion(
      stem: _firstStr(p, const ['stem', 'question', 'text']) ?? '',
      options: options,
      subjectId: p.intOrNull('subject_id'),
      correctIndex: correct,
      selectedIndex: p.intOrNull('selected_index'),
      explanation: _firstStr(p, const ['explanation']),
      sourceRef: _firstStr(p, const ['source_ref', 'source']),
      sourceUrl: _firstStr(p, const ['source_url']),
      year: p.intOrNull('year'),
    );
  }

  final String stem;
  final List<String> options;
  final int? subjectId;
  final int? correctIndex;
  final int? selectedIndex;
  final String? explanation;
  final String? sourceRef;
  final String? sourceUrl;
  final int? year;
}

/// A link to the original news article.
@immutable
class NoteLink {
  const NoteLink({required this.url, this.title});
  final String url;
  final String? title;
}

/// A saved daily note (payload = `DailyNote.toJson()`, bilingual).
@immutable
class BookmarkedNote {
  const BookmarkedNote({
    required this.title,
    required this.summary,
    required this.keyFacts,
    this.titleEn,
    this.summaryEn,
    this.keyFactsEn = const [],
    this.category,
    this.noteDate,
    this.links = const [],
  });

  factory BookmarkedNote.fromPayload(Map<String, dynamic> p) => BookmarkedNote(
    title: _firstStr(p, const ['title', 'title_bn']) ?? '',
    summary: _firstStr(p, const ['summary', 'summary_bn']) ?? '',
    keyFacts: parseFacts(p['key_facts']),
    titleEn: _firstStr(p, const ['title_en']),
    summaryEn: _firstStr(p, const ['summary_en']),
    keyFactsEn: parseFacts(p['key_facts_en']),
    category: _firstStr(p, const ['category']),
    noteDate: p.date('note_date'),
    links: [
      for (final item in (p['source_links'] as List?) ?? const <Object?>[])
        if (item is String && item.isNotEmpty)
          NoteLink(url: item)
        else if (item is Map && item['url'] is String)
          NoteLink(
            url: item['url'] as String,
            title: _firstStr(Map<String, dynamic>.from(item), const ['title', 'source', 'name']),
          ),
    ],
  );

  final String title;
  final String summary;
  final List<String> keyFacts;
  final String? titleEn;
  final String? summaryEn;
  final List<String> keyFactsEn;
  final String? category;
  final DateTime? noteDate;
  final List<NoteLink> links;

  /// English content when the UI is English and a translation exists.
  String titleFor({required bool bangla}) => (!bangla && titleEn != null) ? titleEn! : title;
  String summaryFor({required bool bangla}) => (!bangla && summaryEn != null) ? summaryEn! : summary;
  List<String> factsFor({required bool bangla}) => (!bangla && keyFactsEn.isNotEmpty) ? keyFactsEn : keyFacts;

  /// `key_facts` items may be plain strings or `{fact, tag}` / `{label, value}`.
  static List<String> parseFacts(Object? raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    for (final item in raw) {
      if (item is String && item.trim().isNotEmpty) {
        out.add(item.trim());
      } else if (item is Map) {
        final m = Map<String, dynamic>.from(item);
        final fact = _firstStr(m, const ['fact', 'text', 'value']);
        final label = _firstStr(m, const ['label']);
        if (fact != null) out.add(label == null ? fact : '$label: $fact');
      }
    }
    return out;
  }
}

/// A saved community post (payload = `Post.toJson()` from the feed feature).
@immutable
class BookmarkedPost {
  const BookmarkedPost({
    required this.body,
    this.authorName,
    this.authorUsername,
    this.authorAvatarUrl,
    this.imageUrl,
    this.createdAt,
  });

  factory BookmarkedPost.fromPayload(Map<String, dynamic> p) {
    final author = p.objOrNull('author') ?? const <String, dynamic>{};
    final images = [...p.strings('image_paths'), ...p.strings('image_urls'), ...p.strings('media')];
    return BookmarkedPost(
      body: _firstStr(p, const ['body', 'content', 'text']) ?? '',
      authorName:
          _firstStr(p, const ['author_full_name', 'author_name']) ?? _firstStr(author, const ['full_name', 'name']),
      authorUsername: _firstStr(p, const ['author_username']) ?? _firstStr(author, const ['username']),
      authorAvatarUrl:
          _firstStr(p, const ['author_avatar_url', 'author_avatar']) ?? _firstStr(author, const ['avatar_url']),
      imageUrl: images.where((u) => u.startsWith('http')).firstOrNull,
      createdAt: p.date('created_at'),
    );
  }

  final String body;
  final String? authorName;
  final String? authorUsername;
  final String? authorAvatarUrl;
  final String? imageUrl;
  final DateTime? createdAt;

  String? get displayName => authorName ?? authorUsername;
}

/// Bookmark keys whose removal is still waiting in the offline queue (a later
/// queued restore cancels an earlier removal — last op wins, FIFO).
Set<String> netPendingRemovals(Iterable<QueuedOp> ops, {required String removeOp, required String restoreOp}) {
  final sorted = ops.where((o) => o.type == removeOp || o.type == restoreOp).toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final removed = <String>{};
  for (final op in sorted) {
    final type = BookmarkType.parse(op.payload.strOrNull('item_type'));
    if (type == null) continue;
    final key = bookmarkKey(type, op.payload.str('item_id'));
    if (op.type == removeOp) {
      removed.add(key);
    } else {
      removed.remove(key);
    }
  }
  return removed;
}
