import 'package:flutter/foundation.dart';
import 'package:prostuti/core/utils/json.dart';
import 'package:prostuti/features/feed/data/post.dart';
import 'package:prostuti/features/profile/data/profile.dart';

/// A comment or a one-level reply, as returned by `get_comments`.
@immutable
class Comment {
  const Comment({
    required this.id,
    required this.postId,
    required this.author,
    required this.body,
    required this.createdAt,
    this.parentId,
    this.likeCount = 0,
    this.replyCount = 0,
    this.likedByMe = false,
    this.editedAt,
    this.pendingSync = false,
  });

  factory Comment.fromJson(Map<String, dynamic> j) => Comment(
    id: j.str('id'),
    postId: j.str('post_id'),
    parentId: j.strOrNull('parent_id'),
    author: UserSummary.fromJson(j, prefix: 'author_'),
    body: j.str('body'),
    likeCount: j.integer('like_count'),
    replyCount: j.integer('reply_count'),
    likedByMe: j.boolean('liked_by_me'),
    createdAt: j.dateOr('created_at', DateTime.now()),
    editedAt: j.date('edited_at'),
  );

  /// A row selected straight from `comments` ([columns]) plus the author.
  factory Comment.fromRow(Map<String, dynamic> row, UserSummary author) => Comment.fromJson({
    ...row,
    'author_id': author.id,
    'author_username': author.username,
    'author_full_name': author.fullName,
    'author_avatar_url': author.avatarUrl,
  });

  static const columns = 'id, post_id, parent_id, author_id, body, like_count, reply_count, created_at, edited_at';

  final String id;
  final String postId;
  final String? parentId;
  final UserSummary author;
  final String body;
  final int likeCount;
  final int replyCount;
  final bool likedByMe;
  final DateTime createdAt;
  final DateTime? editedAt;

  /// Written offline and still waiting in the outbox.
  final bool pendingSync;

  bool get isReply => parentId != null;
  Keyset get cursor => Keyset(createdAt, id);

  /// Optimistic like toggle.
  Comment toggledLike() {
    final liked = !likedByMe;
    final count = likeCount + (liked ? 1 : -1);
    return copyWith(likedByMe: liked, likeCount: count < 0 ? 0 : count);
  }

  Comment copyWith({int? likeCount, int? replyCount, bool? likedByMe, bool? pendingSync}) => Comment(
    id: id,
    postId: postId,
    parentId: parentId,
    author: author,
    body: body,
    likeCount: likeCount ?? this.likeCount,
    replyCount: replyCount ?? this.replyCount,
    likedByMe: likedByMe ?? this.likedByMe,
    createdAt: createdAt,
    editedAt: editedAt,
    pendingSync: pendingSync ?? this.pendingSync,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'post_id': postId,
    'parent_id': parentId,
    'author_id': author.id,
    'author_username': author.username,
    'author_full_name': author.fullName,
    'author_avatar_url': author.avatarUrl,
    'body': body,
    'like_count': likeCount,
    'reply_count': replyCount,
    'liked_by_me': likedByMe,
    'created_at': createdAt.toUtc().toIso8601String(),
    'edited_at': editedAt?.toUtc().toIso8601String(),
  };
}
