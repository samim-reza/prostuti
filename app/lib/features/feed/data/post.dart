import 'package:flutter/foundation.dart';
import 'package:prostuti/core/utils/json.dart';
import 'package:prostuti/features/profile/data/profile.dart';

/// The six reactions supported by `public.reaction_type`.
enum ReactionType {
  like('👍'),
  love('❤️'),
  haha('😆'),
  wow('😮'),
  sad('😢'),
  angry('😡');

  ReactionType(this.emoji);

  final String emoji;

  /// Wire value (`like`, `love` …) — identical to the enum name.
  String get wire => name;

  static ReactionType? tryParse(Object? value) {
    if (value == null) return null;
    final s = value.toString();
    for (final r in values) {
      if (r.name == s) return r;
    }
    return null;
  }
}

/// `public.post_visibility`.
enum PostVisibility {
  public('public'),
  friends('friends'),
  onlyMe('only_me');

  PostVisibility(this.wire);

  final String wire;

  static PostVisibility parse(Object? value) =>
      values.firstWhere((v) => v.wire == value?.toString(), orElse: () => PostVisibility.public);
}

/// `posts.kind`.
enum PostKind {
  text('text'),
  examResult('exam_result'),
  noteShare('note_share'),
  achievement('achievement');

  PostKind(this.wire);

  final String wire;

  static PostKind parse(Object? value) => values.firstWhere((v) => v.wire == value?.toString(), orElse: () => text);
}

/// Keyset cursor `(created_at, id)` used by `get_feed` (descending) and
/// `get_comments` (ascending).
@immutable
class Keyset {
  const Keyset(this.createdAt, this.id);

  final DateTime createdAt;
  final String id;

  String get createdAtIso => createdAt.toUtc().toIso8601String();

  @override
  bool operator ==(Object other) => other is Keyset && other.createdAt == createdAt && other.id == id;

  @override
  int get hashCode => Object.hash(createdAt, id);
}

/// Score card payload of an `exam_result` post (built server-side by
/// `share_exam_result`, so it can't be faked).
@immutable
class ExamResultMeta {
  const ExamResultMeta({
    required this.title,
    required this.score,
    required this.maxScore,
    required this.correct,
    required this.wrong,
    required this.total,
    this.sessionId,
    this.examKind,
  });

  factory ExamResultMeta.fromJson(Map<String, dynamic> j) => ExamResultMeta(
    sessionId: j.strOrNull('session_id'),
    title: j.str('title'),
    examKind: j.strOrNull('kind'),
    score: j.dbl('score'),
    maxScore: j.dbl('max_score'),
    correct: j.integer('correct'),
    wrong: j.integer('wrong'),
    total: j.integer('total'),
  );

  final String? sessionId;
  final String title;
  final String? examKind;
  final double score;
  final double maxScore;
  final int correct;
  final int wrong;
  final int total;

  int get skipped => (total - correct - wrong).clamp(0, total);

  /// 0..1 — negative marking can push the score below zero; clamp for the ring.
  double get ratio => maxScore <= 0 ? 0 : (score / maxScore).clamp(0.0, 1.0);
}

/// Result of `react_to_post`.
@immutable
class ReactionResult {
  const ReactionResult({required this.reactionCount, required this.summary, this.myReaction});

  factory ReactionResult.fromJson(Map<String, dynamic> j) => ReactionResult(
    reactionCount: j.integer('reaction_count'),
    summary: parseReactionSummary(j['reaction_summary']),
    myReaction: ReactionType.tryParse(j['my_reaction']),
  );

  final int reactionCount;
  final Map<ReactionType, int> summary;
  final ReactionType? myReaction;
}

/// `{"like": 3, "love": 1}` → typed map (unknown keys and zero counts dropped).
Map<ReactionType, int> parseReactionSummary(Object? raw) {
  if (raw is! Map) return const {};
  final out = <ReactionType, int>{};
  raw.forEach((key, value) {
    final type = ReactionType.tryParse(key);
    final count = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    if (type != null && count > 0) out[type] = count;
  });
  return Map.unmodifiable(out);
}

/// A feed post as returned by `get_feed`.
@immutable
class Post {
  const Post({
    required this.id,
    required this.author,
    required this.createdAt,
    this.body,
    this.imageUrls = const [],
    this.visibility = PostVisibility.public,
    this.kind = PostKind.text,
    this.meta = const {},
    this.reactionCount = 0,
    this.commentCount = 0,
    this.reactionSummary = const {},
    this.myReaction,
    this.editedAt,
    this.pendingSync = false,
  });

  /// Parses a `get_feed` row.
  factory Post.fromJson(Map<String, dynamic> j) => Post(
    id: j.str('id'),
    author: UserSummary.fromJson(j, prefix: 'author_'),
    body: j.strOrNull('body'),
    imageUrls: j.strings('image_paths'),
    visibility: PostVisibility.parse(j['visibility']),
    kind: PostKind.parse(j['kind']),
    meta: j.obj('meta'),
    reactionCount: j.integer('reaction_count'),
    commentCount: j.integer('comment_count'),
    reactionSummary: parseReactionSummary(j['reaction_summary']),
    myReaction: ReactionType.tryParse(j['my_reaction']),
    createdAt: j.dateOr('created_at', DateTime.now()),
    editedAt: j.date('edited_at'),
  );

  /// Parses a row selected straight from `posts` ([columns]) — the author is
  /// not joined there, so the caller supplies it.
  factory Post.fromRow(Map<String, dynamic> row, UserSummary author) => Post.fromJson({...row, ..._authorJson(author)});

  /// Columns selected from `posts` after an insert/update.
  static const columns =
      'id, author_id, body, image_paths, visibility, kind, meta, reaction_count, comment_count, '
      'reaction_summary, created_at, edited_at';

  final String id;
  final UserSummary author;
  final String? body;
  final List<String> imageUrls;
  final PostVisibility visibility;
  final PostKind kind;
  final Map<String, dynamic> meta;
  final int reactionCount;
  final int commentCount;
  final Map<ReactionType, int> reactionSummary;
  final ReactionType? myReaction;
  final DateTime createdAt;
  final DateTime? editedAt;

  /// Written offline and still waiting in the outbox (not on the server yet).
  final bool pendingSync;

  bool get hasBody => body != null && body!.trim().isNotEmpty;
  bool get isEdited => editedAt != null;
  Keyset get cursor => Keyset(createdAt, id);

  ExamResultMeta? get examResult => kind == PostKind.examResult ? ExamResultMeta.fromJson(meta) : null;

  /// The most used reactions, most popular first (ties keep enum order).
  List<ReactionType> topReactions([int max = 3]) {
    final entries = reactionSummary.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.index.compareTo(b.key.index);
      });
    return [for (final e in entries.take(max)) e.key];
  }

  /// Optimistic reducer: what the post looks like after *I* switch my
  /// reaction to [next] (`null` removes it). Pure — used for instant UI and
  /// unit-tested; the server's answer later replaces the counts.
  Post withReaction(ReactionType? next) {
    final prev = myReaction;
    if (prev == next) return this;
    final summary = Map<ReactionType, int>.of(reactionSummary);
    var count = reactionCount;
    if (prev != null) {
      final left = (summary[prev] ?? 0) - 1;
      if (left > 0) {
        summary[prev] = left;
      } else {
        summary.remove(prev);
      }
      count -= 1;
    }
    if (next != null) {
      summary[next] = (summary[next] ?? 0) + 1;
      count += 1;
    }
    return copyWith(
      reactionSummary: Map.unmodifiable(summary),
      reactionCount: count < 0 ? 0 : count,
      myReaction: next,
      clearMyReaction: next == null,
    );
  }

  /// Applies the authoritative counts returned by `react_to_post`.
  Post withServerReaction(ReactionResult r) => copyWith(
    reactionCount: r.reactionCount,
    reactionSummary: r.summary,
    myReaction: r.myReaction,
    clearMyReaction: r.myReaction == null,
  );

  Post copyWith({
    String? body,
    List<String>? imageUrls,
    PostVisibility? visibility,
    int? reactionCount,
    int? commentCount,
    Map<ReactionType, int>? reactionSummary,
    ReactionType? myReaction,
    bool clearMyReaction = false,
    DateTime? editedAt,
    UserSummary? author,
    bool? pendingSync,
  }) => Post(
    id: id,
    author: author ?? this.author,
    body: body ?? this.body,
    imageUrls: imageUrls ?? this.imageUrls,
    visibility: visibility ?? this.visibility,
    kind: kind,
    meta: meta,
    reactionCount: reactionCount ?? this.reactionCount,
    commentCount: commentCount ?? this.commentCount,
    reactionSummary: reactionSummary ?? this.reactionSummary,
    myReaction: clearMyReaction ? null : (myReaction ?? this.myReaction),
    createdAt: createdAt,
    editedAt: editedAt ?? this.editedAt,
    pendingSync: pendingSync ?? this.pendingSync,
  );

  /// Same shape as a `get_feed` row, so cached pages round-trip.
  Map<String, dynamic> toJson() => {
    'id': id,
    ..._authorJson(author),
    'body': body,
    'image_paths': imageUrls,
    'visibility': visibility.wire,
    'kind': kind.wire,
    'meta': meta,
    'reaction_count': reactionCount,
    'comment_count': commentCount,
    'reaction_summary': {for (final e in reactionSummary.entries) e.key.wire: e.value},
    'my_reaction': myReaction?.wire,
    'created_at': createdAt.toUtc().toIso8601String(),
    'edited_at': editedAt?.toUtc().toIso8601String(),
  };

  static Map<String, dynamic> authorJson(UserSummary a) => _authorJson(a);

  static Map<String, dynamic> _authorJson(UserSummary a) => {
    'author_id': a.id,
    'author_username': a.username,
    'author_full_name': a.fullName,
    'author_avatar_url': a.avatarUrl,
  };
}
