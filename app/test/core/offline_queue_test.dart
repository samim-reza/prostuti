import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/offline/offline_queue.dart';

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('prostuti_queue').path);
    await OfflineQueue.instance.init();
  });

  tearDown(OfflineQueue.instance.clear);

  test('runs immediately when online', () async {
    final done = <String>[];
    OfflineQueue.instance.register('test.now', (p) async => done.add(p['v']! as String));
    ConnectivityService.instance.reportSuccess();
    final executed = await OfflineQueue.instance.run('test.now', {'v': 'a'});
    expect(executed, isTrue);
    expect(done, ['a']);
  });

  test('queues while offline and replays in order when back online', () async {
    final done = <String>[];
    OfflineQueue.instance.register('test.later', (p) async => done.add(p['v']! as String));
    ConnectivityService.instance.reportFailure();
    await OfflineQueue.instance.run('test.later', {'v': '1'});
    await OfflineQueue.instance.run('test.later', {'v': '2'});
    expect(done, isEmpty);
    expect(OfflineQueue.instance.pendingCount.value, 2);
    expect(OfflineQueue.instance.pendingOf('test.later').map((o) => o.payload['v']), ['1', '2']);

    ConnectivityService.instance.reportSuccess();
    await OfflineQueue.instance.flush();
    expect(done, ['1', '2']);
    expect(OfflineQueue.instance.pendingCount.value, 0);
  });

  test('network errors keep the op queued', () async {
    var attempts = 0;
    OfflineQueue.instance.register('test.flaky', (p) async {
      attempts++;
      throw const SocketException('no route');
    });
    ConnectivityService.instance.reportFailure();
    await OfflineQueue.instance.run('test.flaky', {});
    ConnectivityService.instance.reportSuccess();
    await OfflineQueue.instance.flush();
    expect(attempts, 1);
    expect(OfflineQueue.instance.pendingCount.value, 1);
  });
}
