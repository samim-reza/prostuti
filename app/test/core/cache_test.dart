import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:prostuti/core/cache/bloom_filter.dart';
import 'package:prostuti/core/cache/cache_store.dart';
import 'package:prostuti/core/cache/cached_fetcher.dart';
import 'package:prostuti/core/cache/lru_cache.dart';
import 'package:prostuti/core/offline/connectivity.dart';

void main() {
  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('prostuti_test').path);
  });

  group('LruCache', () {
    test('evicts the least recently used entry', () {
      final cache = LruCache<String, int>(2)
        ..put('a', 1)
        ..put('b', 2);
      expect(cache.get('a'), 1); // a is now most recent
      cache.put('c', 3); // evicts b
      expect(cache.get('b'), isNull);
      expect(cache.get('a'), 1);
      expect(cache.get('c'), 3);
    });
  });

  group('BloomFilter', () {
    test('has no false negatives and a low false-positive rate', () {
      final bloom = BloomFilter(expectedItems: 2000);
      for (var i = 0; i < 2000; i++) {
        bloom.add('post-$i');
      }
      for (var i = 0; i < 2000; i++) {
        expect(bloom.mightContain('post-$i'), isTrue);
      }
      var falsePositives = 0;
      for (var i = 0; i < 10000; i++) {
        if (bloom.mightContain('other-$i')) falsePositives++;
      }
      expect(falsePositives / 10000, lessThan(0.03));
    });

    test('testAndAdd reports duplicates', () {
      final bloom = BloomFilter(expectedItems: 10);
      expect(bloom.testAndAdd('x'), isFalse);
      expect(bloom.testAndAdd('x'), isTrue);
    });
  });

  group('CachedFetcher', () {
    late CachedFetcher fetcher;

    setUp(() async {
      fetcher = CachedFetcher(await CacheStore.inMemory());
      ConnectivityService.instance.reportSuccess();
    });

    test('coalesces concurrent requests (single-flight)', () async {
      var calls = 0;
      final gate = Completer<int>();
      Future<int> fetch() {
        calls++;
        return gate.future;
      }

      final a = fetcher.get<int>('k', fetch: fetch, encode: (v) => v, decode: (j) => j! as int);
      final b = fetcher.get<int>('k', fetch: fetch, encode: (v) => v, decode: (j) => j! as int);
      gate.complete(42);
      expect(await a, 42);
      expect(await b, 42);
      expect(calls, 1);
    });

    test('serves fresh cache without calling the network', () async {
      var calls = 0;
      Future<int> fetch() async => ++calls;
      await fetcher.get<int>('k2', fetch: fetch, encode: (v) => v, decode: (j) => j! as int);
      await fetcher.get<int>('k2', fetch: fetch, encode: (v) => v, decode: (j) => j! as int);
      expect(calls, 1);
    });

    test('negative results are cached with the short TTL', () async {
      await fetcher.get<List<int>>(
        'empty',
        fetch: () async => <int>[],
        encode: (v) => v,
        decode: (j) => (j! as List).cast<int>(),
        isEmpty: (v) => v.isEmpty,
        policy: const CachePolicy(ttl: Duration(hours: 1), negativeTtl: Duration(seconds: 30)),
      );
      final entry = fetcher.store.read('empty')!;
      expect(entry.expiresAt.difference(entry.storedAt), const Duration(seconds: 30));
    });

    test('falls back to stale data when the network fails', () async {
      await fetcher.store.write('stale', 7, Duration.zero);
      final value = await fetcher.get<int>(
        'stale',
        fetch: () => Future.error(const SocketException('offline')),
        encode: (v) => v,
        decode: (j) => j! as int,
      );
      expect(value, 7);
    });

    test('offline: returns cached data immediately', () async {
      await fetcher.store.write('offline', 5, Duration.zero);
      ConnectivityService.instance.reportFailure();
      final value = await fetcher.get<int>(
        'offline',
        fetch: () => Future.error(const SocketException('offline')),
        encode: (v) => v,
        decode: (j) => j! as int,
      );
      expect(value, 5);
      ConnectivityService.instance.reportSuccess();
    });
  });
}
