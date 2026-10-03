import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/question_bank/data/offline_pack_store.dart';

import '../exam/fixtures.dart';

void main() {
  late OfflinePackStore store;
  List<Question> pack(int subject, List<int> ids) => [
    for (final id in ids)
      Question.fromJson({
        ...questionJson(id, subjectId: subject, topicId: subject * 100 + id % 2),
        'correct_index': id % 4,
        'explanation': 'ব্যাখ্যা $id',
      }),
  ];

  setUp(() => store = OfflinePackStore(MemoryPackStorage(), 'u1'));

  test('save → index summary → load keeps answers and explanations', () async {
    final info = await store.save(7, pack(7, [1, 2, 3]));
    expect(info.count, 3);
    expect(info.bytes, greaterThan(100));
    expect(info.topicIds, {700, 701});
    expect(store.index().keys, [7]);

    final fresh = OfflinePackStore(MemoryPackStorage(), 'u1');
    expect(fresh.index(), isEmpty, reason: 'storage is per instance in tests');

    final loaded = await store.load(7);
    expect(loaded!.map((q) => q.id), [1, 2, 3]);
    expect(loaded.first.correctIndex, 1);
    expect(loaded.first.explanation, 'ব্যাখ্যা 1');
  });

  test('packs are per user and removable', () async {
    final storage = MemoryPackStorage();
    final a = OfflinePackStore(storage, 'a');
    final b = OfflinePackStore(storage, 'b');
    await a.save(1, pack(1, [1]));
    expect(b.index(), isEmpty);
    await a.remove(1);
    expect(a.index(), isEmpty);
    expect(await a.load(1), isNull);
  });

  test('decodes a pack written by another store instance (cold start)', () async {
    final storage = MemoryPackStorage();
    await OfflinePackStore(storage, 'u').save(2, pack(2, [10, 11]));
    final cold = OfflinePackStore(storage, 'u');
    expect((await cold.load(2))!.map((q) => q.id), [10, 11]);
    expect(cold.index()[2]!.count, 2);
  });

  test('seen set and answer buffer', () async {
    await store.markSeen([1, 2]);
    await store.markSeen([2, 3]);
    expect(store.seen(), {1, 2, 3});

    final at = DateTime.utc(2026, 10, 4, 5);
    expect(await store.buffer(PracticeAttempt(clientId: 'c1', questionId: 1, selectedIndex: 2, answeredAt: at)), 1);
    expect(await store.buffer(PracticeAttempt(clientId: 'c2', questionId: 2, selectedIndex: 0, answeredAt: at)), 2);
    final drained = await store.drain();
    expect(drained.map((a) => a.clientId), ['c1', 'c2']);
    expect(drained.first.toJson(), {
      'client_id': 'c1',
      'question_id': 1,
      'selected_index': 2,
      'answered_at': '2026-10-04T05:00:00.000Z',
    });
    expect(store.buffered(), isEmpty);

    await store.restore(drained);
    expect(store.buffered(), hasLength(2));
  });
}
