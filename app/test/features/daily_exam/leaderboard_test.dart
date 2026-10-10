import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/core/cache/cache_store.dart';
import 'package:prostuti/core/cache/cached_fetcher.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/features/daily_exam/data/daily_standing.dart';
import 'package:prostuti/features/daily_exam/data/leaderboard_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// `get_daily_standing` payloads as the live database returns them (scores
/// are numeric(6,2)): 9 participants, ranks 1, 2, 3, 3, 5, 6, 7, 8, 9.
Map<String, dynamic> _payload({Map<String, dynamic>? me, List<Map<String, dynamic>> neighbors = const []}) => {
  'date': '2026-10-04',
  'participants': 9,
  'total_marks': 15,
  'top_score': 15.00,
  'me': me,
  'neighbors': neighbors,
};

Map<String, dynamic> _rung(int rank, double score) => {'rank': rank, 'score': score};

final _middle = _payload(
  me: {'rank': 6, 'score': 12.00, 'percentile': 66.7, 'time_taken_seconds': 100},
  neighbors: [_rung(3, 13.5), _rung(3, 13.5), _rung(5, 13.5), _rung(7, 11), _rung(8, 10), _rung(9, 9.5)],
);
final _top = _payload(
  me: {'rank': 1, 'score': 15.00, 'percentile': 11.1, 'time_taken_seconds': 300},
  neighbors: [_rung(2, 14), _rung(3, 13.5), _rung(3, 13.5)],
);
final _last = _payload(
  me: {'rank': 9, 'score': 9.50, 'percentile': 100.0, 'time_taken_seconds': 120},
  neighbors: [_rung(6, 12), _rung(7, 11), _rung(8, 10)],
);

void main() {
  group('DailyStanding.fromJson', () {
    test('parses me, neighbors, top score and full marks', () {
      final s = DailyStanding.fromJson(_middle);
      expect(s.date, '2026-10-04');
      expect(s.participants, 9);
      expect(s.totalMarks, 15);
      expect(s.topScore, 15);
      expect(s.attempted, isTrue);
      expect(s.hasExam, isTrue);
      expect(s.me!.rank, 6);
      expect(s.me!.score, 12);
      expect(s.me!.timeTakenSeconds, 100);
      expect(s.me!.percentile, 66.7);
      expect(s.neighbors, hasLength(6));
    });

    test('not attempted: participants and top score, no ladder', () {
      final s = DailyStanding.fromJson(_payload());
      expect(s.attempted, isFalse);
      expect(s.hasExam, isTrue);
      expect(s.topScore, 15);
      expect(s.above, isEmpty);
      expect(s.below, isEmpty);
      expect(s.topPercent, isNull);
      expect(s.gapToNext, isNull);
      expect(s.topOutOfView, isFalse);
      expect(s.hasMoreBelow, isFalse);
    });

    test('no exam that day (live payload shape)', () {
      final s = DailyStanding.fromJson(const {
        'me': null,
        'date': '2019-06-01',
        'neighbors': <Object>[],
        'top_score': null,
        'total_marks': null,
        'participants': 0,
      });
      expect(s.hasExam, isFalse);
      expect(s.isEmpty, isTrue);
      expect(s.topScore, isNull);
    });

    test('an exam nobody has taken yet is not "no exam"', () {
      final s = DailyStanding.fromJson(const {'date': '2026-10-04', 'participants': 0, 'total_marks': 20});
      expect(s.hasExam, isTrue);
      expect(s.isEmpty, isTrue);
    });

    test('numeric strings and missing fields are tolerated', () {
      final s = DailyStanding.fromJson(const {
        'participants': '340',
        'total_marks': '15',
        'top_score': '15',
        'me': {'rank': '12', 'score': '13.5'},
      });
      expect(s.participants, 340);
      expect(s.me!.rank, 12);
      expect(s.me!.score, 13.5);
      expect(s.me!.timeTakenSeconds, isNull);
      expect(s.neighbors, isEmpty);
      // Without a server percentile: 12 / 340 = 3.5 % → "Top 4%".
      expect(s.topPercent, 4);
    });

    test('round-trips through toJson (cache encoding)', () {
      final s = DailyStanding.fromJson(_middle);
      expect(DailyStanding.fromJson(s.toJson()).toJson(), s.toJson());
    });
  });

  group('ladder', () {
    test('middle: three above, three below, #1 rung with a gap', () {
      final s = DailyStanding.fromJson(_middle);
      expect(s.above.map((r) => r.rank), [3, 3, 5]);
      expect(s.below.map((r) => r.rank), [7, 8, 9]);
      expect(s.topOutOfView, isTrue);
      expect(s.gapBelowTop, isTrue, reason: 'ranks 1 and 2 sit between #1 and #3');
      expect(s.hasMoreBelow, isFalse, reason: '#9 is last');
      expect(s.topPercent, 67);
      expect(s.gapToNext, (rank: 5, marks: 1.5));
    });

    test('first place: nothing above, no top rung, more below', () {
      final s = DailyStanding.fromJson(_top);
      expect(s.above, isEmpty);
      expect(s.below.map((r) => r.rank), [2, 3, 3]);
      expect(s.topOutOfView, isFalse);
      expect(s.gapToNext, isNull);
      expect(s.hasMoreBelow, isTrue);
      expect(s.topPercent, 12);
    });

    test('last place: Top 100%, nothing below', () {
      final s = DailyStanding.fromJson(_last);
      expect(s.below, isEmpty);
      expect(s.hasMoreBelow, isFalse);
      expect(s.topPercent, 100);
      expect(s.gapToNext, (rank: 8, marks: 0.5));
    });

    test('ties with me go below; a tie is not a gap to close', () {
      final s = DailyStanding.fromJson(
        _payload(
          me: {'rank': 3, 'score': 13.5, 'time_taken_seconds': 250},
          neighbors: [_rung(1, 15), _rung(2, 14), _rung(3, 13.5), _rung(5, 13.5), _rung(6, 12), _rung(7, 11)],
        ),
      );
      expect(s.above.map((r) => r.rank), [1, 2]);
      expect(s.below.map((r) => r.rank), [3, 5, 6, 7]);
      expect(s.topOutOfView, isFalse, reason: '#1 is already on the ladder');
      expect(s.gapToNext, (rank: 2, marks: 0.5));
    });

    test('#2 right below #1: top rung without a gap', () {
      final s = DailyStanding.fromJson(
        _payload(me: {'rank': 3, 'score': 13.5}, neighbors: [_rung(2, 14), _rung(4, 13)]),
      );
      expect(s.topOutOfView, isTrue);
      expect(s.gapBelowTop, isFalse);
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

  group('LeaderboardRepository (offline-first)', () {
    late CacheStore store;
    late LeaderboardRepository repo;

    setUp(() async {
      store = await CacheStore.inMemory();
      // Nothing listens on port 9: every RPC fails like a dead network.
      repo = LeaderboardRepository(
        SupabaseClient('http://127.0.0.1:9', 'test-key', authOptions: const AuthClientOptions(autoRefreshToken: false)),
        CachedFetcher(store),
      );
    });

    tearDown(ConnectivityService.instance.reportSuccess);

    test('a fresh cached standing is served without the network', () async {
      await store.write(LeaderboardRepository.cacheKey('u1', '2026-10-04'), _middle, const Duration(minutes: 5));
      final s = await repo.fetch(userId: 'u1', isoDate: '2026-10-04');
      expect(s.me!.rank, 6);
    });

    test('a stale standing is still served when the network fails', () async {
      await store.write(LeaderboardRepository.cacheKey('u1', '2026-10-04'), _last, Duration.zero);
      final s = await repo.fetch(userId: 'u1', isoDate: '2026-10-04', force: true);
      expect(s.me!.rank, 9);
    });

    test('without a saved copy the network failure surfaces', () async {
      await expectLater(repo.fetch(userId: 'u1', isoDate: '2026-10-03'), throwsA(isA<NetworkFailure>()));
    });

    test('invalidate drops only that user and day', () async {
      final mine = LeaderboardRepository.cacheKey('u1', '2026-10-04');
      final yesterday = LeaderboardRepository.cacheKey('u1', '2026-10-03');
      final other = LeaderboardRepository.cacheKey('u2', '2026-10-04');
      for (final key in [mine, yesterday, other]) {
        await store.write(key, _middle, const Duration(minutes: 5));
      }
      await repo.invalidate('u1', '2026-10-04');
      expect(store.read(mine), isNull);
      expect(store.read(yesterday), isNotNull);
      expect(store.read(other), isNotNull);
    });
  });
}
