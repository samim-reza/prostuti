import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/features/friends/application/relationship_controller.dart';
import 'package:prostuti/features/friends/data/friend_models.dart';
import 'package:prostuti/features/friends/data/relationship.dart';

void main() {
  group('Relationship.fromJson (get_relationship)', () {
    test('parses every status', () {
      expect(Relationship.fromJson(const {'status': 'self'}).status, RelationshipStatus.self);
      expect(Relationship.fromJson(const {'status': 'none'}).status, RelationshipStatus.none);
      expect(Relationship.fromJson(const {'status': 'friends'}).isFriend, isTrue);
      expect(Relationship.fromJson(const {'status': 'blocked'}).isBlocked, isTrue);
      final sent = Relationship.fromJson(const {'status': 'request_sent', 'request_id': 12});
      expect(sent.status, RelationshipStatus.requestSent);
      expect(sent.requestId, 12);
      expect(sent.isPending, isTrue);
      final received = Relationship.fromJson(const {'status': 'request_received', 'request_id': '7'});
      expect(received.status, RelationshipStatus.requestReceived);
      expect(received.requestId, 7);
    });

    test('unknown or missing status falls back to none', () {
      expect(Relationship.fromJson(const {'status': 'weird'}), Relationship.none);
      expect(Relationship.fromJson(const {}), Relationship.none);
    });

    test('send_friend_request answers parse too', () {
      expect(Relationship.fromJson(const {'status': 'request_sent', 'request_id': 1}).requestId, 1);
      expect(Relationship.fromJson(const {'status': 'friends'}), Relationship.friends);
    });

    test('value equality and JSON round trip (offline cache)', () {
      const r = Relationship(RelationshipStatus.requestReceived, requestId: 3);
      expect(Relationship.fromJson(r.toJson()), r);
      expect(Relationship.none.toJson(), {'status': 'none'});
      expect(r == const Relationship(RelationshipStatus.requestReceived, requestId: 4), isFalse);
    });
  });

  group('resolveRelationships (batched lookup)', () {
    const me = 'me';

    test('mirrors get_relationship precedence', () {
      final map = resolveRelationships(
        me: me,
        userIds: ['me', 'friend', 'sentTo', 'from', 'blocked', 'stranger', 'blockedFriend'],
        friendships: [
          {'user_a': 'friend', 'user_b': 'me'},
          {'user_a': 'me', 'user_b': 'blockedFriend'},
        ],
        pendingRequests: [
          {'id': 5, 'sender_id': 'me', 'receiver_id': 'sentTo'},
          {'id': 9, 'sender_id': 'from', 'receiver_id': 'me'},
        ],
        blocks: [
          {'blocked_id': 'blocked'},
          {'blocked_id': 'blockedFriend'},
        ],
      );
      expect(map['me'], Relationship.self);
      expect(map['friend'], Relationship.friends);
      expect(map['sentTo'], const Relationship(RelationshipStatus.requestSent, requestId: 5));
      expect(map['from'], const Relationship(RelationshipStatus.requestReceived, requestId: 9));
      expect(map['blocked'], Relationship.blocked);
      expect(map['stranger'], Relationship.none);
      expect(map['blockedFriend'], Relationship.blocked, reason: 'blocked wins over friends');
    });
  });

  group('RelationshipSeeds', () {
    test('is a bounded LRU', () {
      final seeds = RelationshipSeeds(capacity: 2)
        ..put('a', Relationship.friends)
        ..put('b', Relationship.none);
      expect(seeds['a'], Relationship.friends); // touch a → b is now oldest
      seeds.put('c', Relationship.blocked);
      expect(seeds['b'], isNull);
      expect(seeds['a'], Relationship.friends);
      expect(seeds['c'], Relationship.blocked);
    });
  });

  group('friend models', () {
    test('FriendRequest parses and round-trips', () {
      final r = FriendRequest.fromJson(const {
        'request_id': 1,
        'user_id': 'u2',
        'username': 'qa_karim',
        'full_name': 'QA Karim',
        'avatar_url': null,
        'mutual_friends': 3,
        'created_at': '2026-10-03T21:12:07.459609+00:00',
      }, incoming: true);
      expect(r.id, 1);
      expect(r.user.id, 'u2');
      expect(r.user.displayName, 'QA Karim');
      expect(r.mutualFriends, 3);
      expect(r.incoming, isTrue);
      final copy = FriendRequest.fromJson(r.toJson(), incoming: true);
      expect(copy.user.id, 'u2');
      expect(copy.createdAt, r.createdAt);
    });

    test('Friend parses get_friends rows', () {
      final f = Friend.fromJson(const {
        'id': 'u3',
        'username': 'nadia',
        'full_name': null,
        'avatar_url': null,
        'bio': 'BCS 47',
        'friends_since': '2026-10-03T21:12:14.38002+00:00',
      });
      expect(f.user.displayName, 'nadia');
      expect(f.bio, 'BCS 47');
      expect(Friend.fromJson(f.toJson()).friendsSince, f.friendsSince);
    });

    test('FriendSuggestion reasons', () {
      FriendSuggestion parse(String reason) => FriendSuggestion.fromJson({
        'id': 'x',
        'username': 'x',
        'district': 'ঢাকা',
        'mutual_friends': 2,
        'reason': reason,
      });
      expect(parse('mutual').reason, SuggestionReason.mutual);
      expect(parse('district').reason, SuggestionReason.district);
      expect(parse('same_exam').reason, SuggestionReason.sameExam);
      expect(parse('new').reason, SuggestionReason.newcomer);
      expect(parse('???').reason, SuggestionReason.newcomer);
      expect(parse('mutual').district, 'ঢাকা');
      expect(parse('mutual').mutualFriends, 2);
    });
  });
}
