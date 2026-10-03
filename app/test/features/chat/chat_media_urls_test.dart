import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/features/chat/data/chat_media_urls.dart';
import 'package:prostuti/features/chat/data/realtime_gate.dart';

void main() {
  group('ChatMediaUrls', () {
    late DateTime now;
    late List<List<String>> calls;

    ChatMediaUrls build({Completer<void>? gate}) {
      calls = [];
      return ChatMediaUrls((paths, expiresIn) async {
        calls.add(paths);
        expect(expiresIn, 3600);
        if (gate != null) await gate.future;
        return {for (final p in paths) p: 'https://signed/$p?t=${now.millisecondsSinceEpoch}'};
      }, clock: () => now);
    }

    setUp(() => now = DateTime(2026, 10, 4, 12));

    test('caches a signed URL until shortly before it expires', () async {
      final urls = build();
      final first = await urls.get('c/a.webp');
      expect(urls.peek('c/a.webp'), first);
      expect(calls, hasLength(1));

      now = now.add(const Duration(minutes: 50));
      expect(await urls.get('c/a.webp'), first);
      expect(calls, hasLength(1));

      now = now.add(const Duration(minutes: 6)); // inside the 5-minute renewal window
      expect(urls.peek('c/a.webp'), isNull);
      final renewed = await urls.get('c/a.webp');
      expect(renewed, isNot(first));
      expect(calls, hasLength(2));
    });

    test('single-flight: concurrent requests share one call', () async {
      final gate = Completer<void>();
      final urls = build(gate: gate);
      final a = urls.get('c/x.webp');
      final b = urls.get('c/x.webp');
      gate.complete();
      expect(await a, await b);
      expect(calls, hasLength(1));
    });

    test('prefetch signs only missing paths, in one request', () async {
      final urls = build();
      await urls.get('c/1.webp');
      await urls.prefetch(['c/1.webp', 'c/2.webp', 'c/3.webp', 'c/2.webp']);
      expect(calls, [
        ['c/1.webp'],
        ['c/2.webp', 'c/3.webp'],
      ]);
      expect(urls.peek('c/3.webp'), isNotNull);
      await urls.prefetch(['c/2.webp']);
      expect(calls, hasLength(2));
    });

    test('LRU evicts the least recently used path', () async {
      calls = [];
      final urls = ChatMediaUrls((paths, _) async => {for (final p in paths) p: 'u:$p'}, capacity: 2);
      await urls.get('a');
      await urls.get('b');
      urls.peek('a'); // a is now most recent
      await urls.get('c'); // evicts b
      expect(urls.peek('a'), 'u:a');
      expect(urls.peek('b'), isNull);
      expect(urls.peek('c'), 'u:c');
    });

    test('a failed batch surfaces through get() without unhandled errors', () async {
      var fail = true;
      final urls = ChatMediaUrls((paths, _) async {
        if (fail) throw StateError('offline');
        return {for (final p in paths) p: 'ok:$p'};
      });
      await urls.prefetch(['p1', 'p2']);
      expect(urls.peek('p1'), isNull);
      fail = false;
      expect(await urls.get('p1'), 'ok:p1');
    });
  });

  group('connectWhenOnline', () {
    test('connects at once when online; reconnect hook on every return', () async {
      final changes = StreamController<bool>.broadcast();
      var connects = 0;
      var reconnects = 0;
      final cancel = connectWhenOnline(
        connect: () => connects++,
        onReconnect: () => reconnects++,
        isOnline: true,
        changes: changes.stream,
      );
      expect(connects, 1);
      changes
        ..add(false)
        ..add(true);
      await Future<void>.delayed(Duration.zero);
      expect((connects, reconnects), (1, 1));
      cancel();
      changes.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(reconnects, 1);
      await changes.close();
    });

    test('defers the subscription until connectivity returns', () async {
      final changes = StreamController<bool>.broadcast();
      var connects = 0;
      var reconnects = 0;
      final cancel = connectWhenOnline(
        connect: () => connects++,
        onReconnect: () => reconnects++,
        isOnline: false,
        changes: changes.stream,
      );
      expect(connects, 0);
      changes.add(true);
      await Future<void>.delayed(Duration.zero);
      // Connected now, and told to refetch what was missed while offline.
      expect((connects, reconnects), (1, 1));
      cancel();
      await changes.close();
    });
  });
}
