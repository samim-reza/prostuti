import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/core/offline/offline_queue.dart';
import 'package:prostuti/features/bookmarks/data/bookmark.dart';

void main() {
  group('Bookmark row', () {
    test('parses and round-trips', () {
      final b = Bookmark.fromJson(const {
        'item_type': 'note',
        'item_id': '42',
        'payload': {'title': 'T'},
        'created_at': '2026-10-03T21:27:33.590301+00:00',
      });
      expect(b.type, BookmarkType.note);
      expect(b.key, 'note:42');
      expect(b.createdAt, DateTime.utc(2026, 10, 3, 21, 27, 33, 590, 301));
      final again = Bookmark.fromJson(b.toJson());
      expect(again.key, b.key);
      expect(again.createdAt, b.createdAt);
      expect(again.payload, b.payload);
    });

    test('keyset cursor builds a quoted PostgREST or-filter', () {
      final c = BookmarkCursor(DateTime.utc(2026, 10, 3, 21, 27, 33, 590, 301), '900003');
      expect(
        c.orFilter,
        'created_at.lt."2026-10-03T21:27:33.590301Z",'
        'and(created_at.eq."2026-10-03T21:27:33.590301Z",item_id.lt."900003")',
      );
    });
  });

  group('question payload (Question.toJson shape)', () {
    test('keeps answer details', () {
      final q = BookmarkedQuestion.fromPayload(const {
        'id': 7,
        'subject_id': 3,
        'stem': 'বাংলাদেশের জাতীয় ফুল কোনটি?',
        'options': ['শাপলা', 'গোলাপ', 'জবা', 'বেলি'],
        'correct_index': 0,
        'selected_index': 2,
        'explanation': 'শাপলা জাতীয় ফুল।',
        'source_ref': '৩৫তম বিসিএস',
        'year': 2014,
      });
      expect(q.stem, startsWith('বাংলাদেশের'));
      expect(q.options, hasLength(4));
      expect(q.correctIndex, 0);
      expect(q.selectedIndex, 2);
      expect(q.subjectId, 3);
      expect(q.explanation, isNotNull);
      expect(q.sourceRef, '৩৫তম বিসিএস');
      expect(q.year, 2014);
    });

    test('tolerates missing / out-of-range answers and alternate keys', () {
      final q = BookmarkedQuestion.fromPayload(const {
        'question': 'Q?',
        'options': ['a', 'b'],
        'correctIndex': 5,
      });
      expect(q.stem, 'Q?');
      expect(q.correctIndex, isNull);
      expect(BookmarkedQuestion.fromPayload(const {}).stem, '');
    });
  });

  group('note payload (DailyNote.toJson shape)', () {
    final payload = {
      'id': 1,
      'note_date': '2026-10-01',
      'category': 'international',
      'title': 'জাতিসংঘ অধিবেশন',
      'summary': 'সারাংশ',
      'title_en': 'UN session',
      'summary_en': 'Summary',
      'key_facts': [
        {'fact': 'সভাপতি: ক', 'tag': 'ব্যক্তি'},
        'সরল তথ্য',
        {'label': 'স্থান', 'value': 'নিউইয়র্ক'},
        {'nothing': true},
      ],
      'key_facts_en': [
        {'fact': 'President: A'},
      ],
      'source_links': [
        {'url': 'https://example.com/a', 'source': 'Prothom Alo'},
        'https://example.com/b',
        {'title': 'no url'},
      ],
    };

    test('parses facts in every supported shape', () {
      final n = BookmarkedNote.fromPayload(payload);
      expect(n.keyFacts, ['সভাপতি: ক', 'সরল তথ্য', 'স্থান: নিউইয়র্ক']);
      expect(n.category, 'international');
      expect(n.noteDate, DateTime(2026, 10));
      expect(n.links.map((e) => e.url), ['https://example.com/a', 'https://example.com/b']);
      expect(n.links.first.title, 'Prothom Alo');
    });

    test('switches language when a translation exists', () {
      final n = BookmarkedNote.fromPayload(payload);
      expect(n.titleFor(bangla: true), 'জাতিসংঘ অধিবেশন');
      expect(n.titleFor(bangla: false), 'UN session');
      expect(n.factsFor(bangla: false), ['President: A']);
      final bnOnly = BookmarkedNote.fromPayload(const {'title': 'শুধু বাংলা', 'summary': 'স'});
      expect(bnOnly.titleFor(bangla: false), 'শুধু বাংলা');
      expect(bnOnly.factsFor(bangla: false), isEmpty);
    });
  });

  group('post payload', () {
    test('feed Post.toJson shape', () {
      final p = BookmarkedPost.fromPayload(const {
        'id': 'abc',
        'author_full_name': 'রহিম',
        'author_username': 'qa_rahim',
        'author_avatar_url': 'https://cdn/a.webp',
        'body': 'আজকের প্রস্তুতি',
        'image_paths': ['uploads/raw.webp', 'https://cdn/p.webp'],
        'created_at': '2026-10-02T10:00:00Z',
      });
      expect(p.displayName, 'রহিম');
      expect(p.authorAvatarUrl, 'https://cdn/a.webp');
      expect(p.imageUrl, 'https://cdn/p.webp');
      expect(p.createdAt, DateTime.utc(2026, 10, 2, 10));
    });

    test('nested author object', () {
      final p = BookmarkedPost.fromPayload(const {
        'content': 'hello',
        'author': {'username': 'karim', 'avatar_url': 'https://cdn/k.webp'},
      });
      expect(p.body, 'hello');
      expect(p.displayName, 'karim');
      expect(p.imageUrl, isNull);
    });
  });

  test('pending removals: last queued op wins', () {
    QueuedOp op(String type, String itemType, String id, int second) => QueuedOp(
      id: '$type$id$second',
      type: type,
      payload: {'item_type': itemType, 'item_id': id},
      createdAt: DateTime(2026, 10, 4, 10, 0, second),
    );
    final pending = netPendingRemovals(
      [
        op('r', 'question', '1', 1),
        op('r', 'note', '2', 2),
        op('a', 'note', '2', 3), // undo after removal
        op('a', 'post', '3', 4),
        op('r', 'post', '3', 5), // removal after restore
        op('other', 'post', '9', 6),
      ],
      removeOp: 'r',
      restoreOp: 'a',
    );
    expect(pending, {'question:1', 'post:3'});
  });
}
