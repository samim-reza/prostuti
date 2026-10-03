import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/features/feed/data/comment.dart';
import 'package:prostuti/features/feed/data/post.dart';
import 'package:prostuti/features/profile/data/profile.dart';

Map<String, dynamic> _row({
  Map<String, dynamic>? summary,
  String? myReaction,
  String kind = 'text',
  Map<String, dynamic> meta = const {},
}) => {
  'id': 'p1',
  'author_id': 'u1',
  'author_username': 'rahim_bcs',
  'author_full_name': 'রহিম উদ্দিন',
  'author_avatar_url': null,
  'body': 'আজ ৫০টি প্রশ্ন অনুশীলন করলাম',
  'image_paths': ['https://x.supabase.co/storage/v1/object/public/post-media/u1/a.webp'],
  'visibility': 'friends',
  'kind': kind,
  'meta': meta,
  'reaction_count': 4,
  'comment_count': 2,
  'reaction_summary': summary ?? {'like': 2, 'love': 1, 'wow': 1},
  'my_reaction': myReaction,
  'created_at': '2026-10-03T21:11:53.338105+00:00',
  'edited_at': null,
};

void main() {
  group('Post.fromJson', () {
    test('parses a get_feed row with author, reactions and visibility', () {
      final p = Post.fromJson(_row(myReaction: 'love'));
      expect(p.id, 'p1');
      expect(p.author.id, 'u1');
      expect(p.author.username, 'rahim_bcs');
      expect(p.author.displayName, 'রহিম উদ্দিন');
      expect(p.visibility, PostVisibility.friends);
      expect(p.kind, PostKind.text);
      expect(p.imageUrls, hasLength(1));
      expect(p.reactionCount, 4);
      expect(p.commentCount, 2);
      expect(p.reactionSummary, {ReactionType.like: 2, ReactionType.love: 1, ReactionType.wow: 1});
      expect(p.myReaction, ReactionType.love);
      expect(p.createdAt.toUtc(), DateTime.utc(2026, 10, 3, 21, 11, 53, 338, 105));
      expect(p.isEdited, isFalse);
      expect(p.pendingSync, isFalse);
    });

    test('drops unknown reaction keys and non-positive counts', () {
      final p = Post.fromJson(_row(summary: {'like': 3, 'meh': 5, 'sad': 0, 'angry': '2'}));
      expect(p.reactionSummary, {ReactionType.like: 3, ReactionType.angry: 2});
    });

    test('null my_reaction and only_me visibility', () {
      final p = Post.fromJson({..._row(), 'visibility': 'only_me'});
      expect(p.myReaction, isNull);
      expect(p.visibility, PostVisibility.onlyMe);
    });

    test('topReactions orders by count, ties by enum order, max 3', () {
      final p = Post.fromJson(_row(summary: {'wow': 2, 'like': 2, 'love': 5, 'sad': 1}));
      expect(p.topReactions(), [ReactionType.love, ReactionType.like, ReactionType.wow]);
      expect(p.topReactions(1), [ReactionType.love]);
    });

    test('exam_result meta becomes a score card', () {
      final p = Post.fromJson(
        _row(
          kind: 'exam_result',
          meta: {
            'session_id': 's-1',
            'title': 'বিসিএস মডেল টেস্ট ১',
            'kind': 'model_test',
            'score': 152.5,
            'max_score': 200,
            'correct': 160,
            'wrong': 15,
            'total': 200,
          },
        ),
      );
      final exam = p.examResult!;
      expect(p.kind, PostKind.examResult);
      expect(exam.sessionId, 's-1');
      expect(exam.title, 'বিসিএস মডেল টেস্ট ১');
      expect(exam.score, 152.5);
      expect(exam.maxScore, 200);
      expect(exam.correct, 160);
      expect(exam.wrong, 15);
      expect(exam.total, 200);
      expect(exam.skipped, 25);
      expect(exam.ratio, closeTo(0.7625, 1e-9));
    });

    test('exam ratio is clamped for negative scores and zero max', () {
      expect(const ExamResultMeta(title: '', score: -3, maxScore: 50, correct: 0, wrong: 6, total: 50).ratio, 0);
      expect(const ExamResultMeta(title: '', score: 5, maxScore: 0, correct: 5, wrong: 0, total: 5).ratio, 0);
    });

    test('a text post has no exam result', () {
      expect(Post.fromJson(_row()).examResult, isNull);
    });

    test('toJson round-trips through fromJson (offline cache)', () {
      final original = Post.fromJson(_row(myReaction: 'wow'));
      final copy = Post.fromJson(original.toJson());
      expect(copy.id, original.id);
      expect(copy.author.displayName, original.author.displayName);
      expect(copy.reactionSummary, original.reactionSummary);
      expect(copy.myReaction, ReactionType.wow);
      expect(copy.visibility, original.visibility);
      expect(copy.imageUrls, original.imageUrls);
      expect(copy.createdAt, original.createdAt);
    });

    test('fromRow attaches the supplied author', () {
      final p = Post.fromRow(const {
        'id': 'p9',
        'author_id': 'me',
        'body': 'hi',
        'visibility': 'public',
        'created_at': '2026-10-04T00:00:00Z',
      }, const UserSummary(id: 'me', username: 'me_user', fullName: 'Me'));
      expect(p.author.username, 'me_user');
      expect(p.author.displayName, 'Me');
      expect(p.reactionCount, 0);
    });
  });

  group('ReactionResult', () {
    test('parses react_to_post response', () {
      final r = ReactionResult.fromJson(const {
        'my_reaction': 'like',
        'reaction_count': 2,
        'reaction_summary': {'like': 1, 'love': 1},
      });
      expect(r.myReaction, ReactionType.like);
      expect(r.reactionCount, 2);
      expect(r.summary, {ReactionType.like: 1, ReactionType.love: 1});
    });

    test('null my_reaction after removing', () {
      final r = ReactionResult.fromJson(const {
        'my_reaction': null,
        'reaction_count': 0,
        'reaction_summary': <String, int>{},
      });
      expect(r.myReaction, isNull);
      expect(r.summary, isEmpty);
    });
  });

  group('Comment', () {
    final json = {
      'id': 'c1',
      'post_id': 'p1',
      'parent_id': null,
      'author_id': 'u2',
      'author_username': 'karim',
      'author_full_name': null,
      'author_avatar_url': null,
      'body': 'দারুণ!',
      'like_count': 1,
      'reply_count': 3,
      'liked_by_me': false,
      'created_at': '2026-10-03T21:12:00.481399+00:00',
      'edited_at': null,
    };

    test('parses get_comments rows', () {
      final c = Comment.fromJson(json);
      expect(c.author.displayName, 'karim');
      expect(c.isReply, isFalse);
      expect(c.replyCount, 3);
      expect(c.cursor.id, 'c1');
    });

    test('toggledLike flips state and count without going negative', () {
      final c = Comment.fromJson(json);
      final liked = c.toggledLike();
      expect(liked.likedByMe, isTrue);
      expect(liked.likeCount, 2);
      expect(liked.toggledLike().likeCount, 1);
      final zero = Comment.fromJson({...json, 'like_count': 0, 'liked_by_me': true});
      expect(zero.toggledLike().likeCount, 0);
    });

    test('toJson round-trips', () {
      final c = Comment.fromJson({...json, 'parent_id': 'c0'});
      final copy = Comment.fromJson(c.toJson());
      expect(copy.parentId, 'c0');
      expect(copy.body, c.body);
      expect(copy.createdAt, c.createdAt);
    });
  });
}
