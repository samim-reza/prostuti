import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/features/chat/data/chat_models.dart';

void main() {
  // Shapes captured from the live backend (get_conversations / PostgREST).
  const conversationRow = {
    'id': '65c79912-9439-43cb-a63d-c45e603bfe01',
    'kind': 'direct',
    'title': null,
    'avatar_url': null,
    'other_user_id': '1427f9a4-eb1c-4bb1-a7bb-feffdacf1988',
    'other_username': 'qa_rahim',
    'other_full_name': 'QA Rahim',
    'other_avatar_url': null,
    'last_message_at': '2026-10-03T21:12:29.975199+00:00',
    'last_message_preview': 'আসসালামু আলাইকুম! কেমন আছেন?',
    'last_message_sender': '1427f9a4-eb1c-4bb1-a7bb-feffdacf1988',
    'unread_count': 1,
    'muted': false,
    'member_count': 2,
  };

  const messageRow = {
    'id': 'fac001a7-fd98-4665-873a-52430eeed1e2',
    'conversation_id': '65c79912-9439-43cb-a63d-c45e603bfe01',
    'sender_id': '1427f9a4-eb1c-4bb1-a7bb-feffdacf1988',
    'kind': 'text',
    'body': 'আসসালামু আলাইকুম! কেমন আছেন?',
    'media_path': null,
    'reply_to_id': null,
    'created_at': '2026-10-03T21:12:29.975199+00:00',
    'edited_at': null,
    'deleted_at': null,
  };

  group('ConversationSummary', () {
    test('parses a get_conversations row', () {
      final c = ConversationSummary.fromJson(Map<String, dynamic>.from(conversationRow));
      expect(c.kind, ConversationKind.direct);
      expect(c.isGroup, isFalse);
      expect(c.otherUser?.id, '1427f9a4-eb1c-4bb1-a7bb-feffdacf1988');
      expect(c.displayName, 'QA Rahim');
      expect(c.unreadCount, 1);
      expect(c.lastMessageAt, DateTime.utc(2026, 10, 3, 21, 12, 29, 975, 199));
    });

    test('toJson round-trips (disk cache)', () {
      final c = ConversationSummary.fromJson(Map<String, dynamic>.from(conversationRow));
      final back = ConversationSummary.fromJson(c.toJson());
      expect(back.toJson(), c.toJson());
    });

    test('groups use their title and have no other user', () {
      final g = ConversationSummary.fromJson(const {
        'id': 'g',
        'kind': 'group',
        'title': '  বিসিএস স্টাডি  ',
        'other_user_id': null,
        'member_count': 5,
      });
      expect(g.isGroup, isTrue);
      expect(g.otherUser, isNull);
      expect(g.displayName, 'বিসিএস স্টাডি');
      expect(g.memberCount, 5);
    });
  });

  group('ConversationDetail', () {
    test('parses embedded members with profiles', () {
      final d = ConversationDetail.fromJson(const {
        'id': 'c',
        'kind': 'direct',
        'title': null,
        'created_by': 'me',
        'conversation_members': [
          {
            'role': 'member',
            'muted': false,
            'user_id': 'me',
            'profiles': {'id': 'me', 'username': 'qa_rahim', 'full_name': 'QA Rahim', 'avatar_url': null},
            'last_read_at': '2026-10-03T21:12:29.975199+00:00',
          },
          {
            'role': 'member',
            'muted': true,
            'user_id': 'other',
            'profiles': {'id': 'other', 'username': 'qa_karim', 'full_name': null, 'avatar_url': null},
            'last_read_at': '2026-10-03T21:12:15.638061+00:00',
          },
        ],
      });
      expect(d.members, hasLength(2));
      expect(d.others('me').single.userId, 'other');
      expect(d.otherUser('me')?.displayName, 'qa_karim');
      expect(d.displayName('me'), 'qa_karim');
      expect(d.member('other')?.muted, isTrue);
      expect(ConversationDetail.fromJson(d.toJson()).toJson(), d.toJson());
    });
  });

  group('ChatMessage', () {
    test('parses a messages row', () {
      final m = ChatMessage.fromJson(Map<String, dynamic>.from(messageRow));
      expect(m.kind, MessageKind.text);
      expect(m.status, MessageStatus.sent);
      expect(m.isDeleted, isFalse);
      expect(m.body, startsWith('আসসালামু'));
    });

    test('toInsert only carries insertable columns', () {
      final m = ChatMessage.fromJson(Map<String, dynamic>.from(messageRow));
      expect(m.toInsert().keys, {'id', 'conversation_id', 'sender_id', 'kind', 'body', 'media_path', 'reply_to_id'});
    });

    test('queue payload restores a "sending" bubble after a restart', () {
      final draft = ChatMessage(
        id: 'q1',
        conversationId: 'c',
        senderId: 'me',
        body: 'offline hello',
        replyToId: 'r1',
        createdAt: DateTime.utc(2026, 10, 4, 1, 2, 3),
        status: MessageStatus.sending,
      );
      final restored = ChatMessage.fromQueuePayload(draft.toQueuePayload());
      expect(restored.id, 'q1');
      expect(restored.status, MessageStatus.sending);
      expect(restored.replyToId, 'r1');
      expect(restored.createdAt, draft.createdAt);
      expect(restored.toInsert(), draft.toInsert());
    });

    test('toJson round-trips (latest page cache)', () {
      final m = ChatMessage.fromJson(Map<String, dynamic>.from(messageRow)).copyWith(deletedAt: DateTime.utc(2026));
      final back = ChatMessage.fromJson(m.toJson());
      expect(back.toJson(), m.toJson());
      expect(back.isDeleted, isTrue);
    });

    test('unknown kinds fall back to text; image/system parse', () {
      expect(MessageKind.parse('image'), MessageKind.image);
      expect(MessageKind.parse('system'), MessageKind.system);
      expect(MessageKind.parse('sticker'), MessageKind.text);
    });
  });
}
