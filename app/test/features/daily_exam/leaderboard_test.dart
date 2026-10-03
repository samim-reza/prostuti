import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/features/daily_exam/data/daily_leaderboard.dart';
import 'package:prostuti/features/daily_exam/data/leaderboard_repository.dart';

Map<String, dynamic> _entry(int rank, String id, double score, int secs) => {
  'rank': rank,
  'user_id': id,
  'username': 'user_$id',
  'full_name': id == 'u2' ? null : 'Name $id',
  'avatar_url': null,
  'score': score,
  'time_taken_seconds': secs,
};

Map<String, dynamic> _payload({Map<String, dynamic>? me}) => {
  'date': '2026-10-04',
  'participants': 42,
  'entries': [
    _entry(1, 'u1', 19.5, 410),
    _entry(2, 'u2', 18, 380),
    _entry(2, 'u3', 18, 380),
    _entry(4, 'u4', 15.5, 590),
    _entry(5, 'u5', 12, 600),
  ],
  'me': me,
};

void main() {
  group('DailyLeaderboard.fromJson', () {
    test('parses entries, participants and me', () {
      final b = DailyLeaderboard.fromJson(_payload(me: {'rank': 17, 'score': 9.5, 'time_taken_seconds': 540}));
      expect(b.date, '2026-10-04');
      expect(b.participants, 42);
      expect(b.entries, hasLength(5));
      expect(b.entries.first.score, 19.5);
      expect(b.entries[1].displayName, 'user_u2', reason: 'falls back to username');
      expect(b.entries.first.displayName, 'Name u1');
      expect(b.me!.rank, 17);
      expect(b.me!.score, 9.5);
      expect(b.me!.timeTakenSeconds, 540);
      expect(b.podium.map((e) => e.userId), ['u1', 'u2', 'u3']);
      expect(b.rest.map((e) => e.userId), ['u4', 'u5']);
    });

    test('empty board (live payload shape)', () {
      final b = DailyLeaderboard.fromJson(const {
        'me': null,
        'date': '2026-10-04',
        'entries': <Object>[],
        'participants': 0,
      });
      expect(b.isEmpty, isTrue);
      expect(b.me, isNull);
      expect(b.podium, isEmpty);
      expect(b.rest, isEmpty);
    });

    test('numeric strings and missing fields are tolerated', () {
      final b = DailyLeaderboard.fromJson(const {
        'participants': '3',
        'entries': [
          {'rank': '1', 'user_id': 'x', 'username': 'x', 'score': '7.5'},
        ],
      });
      expect(b.participants, 3);
      expect(b.entries.single.rank, 1);
      expect(b.entries.single.score, 7.5);
      expect(b.entries.single.timeTakenSeconds, isNull);
    });

    test('round-trips through toJson (cache encoding)', () {
      final b = DailyLeaderboard.fromJson(_payload(me: {'rank': 2, 'score': 18, 'time_taken_seconds': 380}));
      final again = DailyLeaderboard.fromJson(b.toJson());
      expect(again.toJson(), b.toJson());
    });
  });

  group('pinnedStanding (pin my rank)', () {
    test('null when I have no result', () {
      final b = DailyLeaderboard.fromJson(_payload());
      expect(pinnedStanding(b, 'u9'), isNull);
    });

    test('null when my row is already in the list', () {
      final b = DailyLeaderboard.fromJson(_payload(me: {'rank': 4, 'score': 15.5, 'time_taken_seconds': 590}));
      expect(pinnedStanding(b, 'u4'), isNull);
    });

    test('pinned when I rank outside the fetched list', () {
      final b = DailyLeaderboard.fromJson(_payload(me: {'rank': 17, 'score': 9.5, 'time_taken_seconds': 540}));
      expect(pinnedStanding(b, 'me')?.rank, 17);
    });

    test('pinned when outside the visible slice (top-5 preview of a bigger board)', () {
      final b = DailyLeaderboard.fromJson(_payload(me: {'rank': 5, 'score': 12, 'time_taken_seconds': 600}));
      expect(pinnedStanding(b, 'u5', visible: b.entries.take(3)), isNotNull);
      expect(pinnedStanding(b, 'u5', visible: b.entries), isNull);
    });

    test('without a user id, falls back to rank+score+time matching', () {
      final inList = DailyLeaderboard.fromJson(_payload(me: {'rank': 4, 'score': 15.5, 'time_taken_seconds': 590}));
      expect(pinnedStanding(inList, null), isNull);
      final outside = DailyLeaderboard.fromJson(_payload(me: {'rank': 30, 'score': 2, 'time_taken_seconds': 100}));
      expect(pinnedStanding(outside, null)?.rank, 30);
    });
  });

  group('leaderboard caching', () {
    test('today short TTL, past days long TTL', () {
      final today = leaderboardPolicy('2026-10-04', todayIso: '2026-10-04');
      expect(today.ttl, const Duration(minutes: 1));
      final past = leaderboardPolicy('2026-10-01', todayIso: '2026-10-04');
      expect(past.ttl, greaterThanOrEqualTo(const Duration(hours: 6)));
      expect(past.negativeTtl, lessThanOrEqualTo(past.ttl));
    });

    test('lastBdDays: 7 days newest first, across month boundaries', () {
      final days = lastBdDays(7, today: DateTime.utc(2026, 10, 3));
      expect(days, hasLength(7));
      expect(days.first, DateTime.utc(2026, 10, 3));
      expect(days[2], DateTime.utc(2026, 10));
      expect(days[3], DateTime.utc(2026, 9, 30));
      expect(days.last, DateTime.utc(2026, 9, 27));
    });
  });
}
