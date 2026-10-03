import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/core/cache/cache_store.dart';
import 'package:prostuti/features/exam/data/exam_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fixtures.dart';

void main() {
  late CacheStore store;
  late ExamRepository repo;

  setUp(() async {
    store = await CacheStore.inMemory();
    repo = ExamRepository(
      SupabaseClient('http://127.0.0.1:9', 'test-key', authOptions: const AuthClientOptions(autoRefreshToken: false)),
      store,
    );
  });

  test('a cached session loads without the network', () async {
    final s = session(id: 'abc', questions: 5);
    await repo.cacheSession(s);
    final loaded = await repo.loadSession('abc');
    expect(loaded.sessionId, 'abc');
    expect(loaded.questions, hasLength(5));
    expect(store.read('exam_session:abc')!.expiresAt.isAfter(s.deadlineAt), isTrue, reason: 'deadline + 1 h grace');
  });

  test('a session past its grace period is not served from cache', () async {
    final old = session(id: 'old', deadline: DateTime.now().subtract(const Duration(hours: 2)));
    await store.write('exam_session:old', old.toJson(), Duration.zero);
    expect(repo.cachedSession('old'), isNull);
  });

  test('answers and flags persist per session', () async {
    await repo.saveAnswers('s1', {101: 2, 102: 0});
    await repo.saveFlags('s1', {103});
    expect(repo.savedAnswers('s1'), {101: 2, 102: 0});
    expect(repo.savedFlags('s1'), {103});
    expect(repo.savedAnswers('other'), isEmpty);
  });

  test('cached results and history pages decode', () async {
    await store.write('exam_result:s1', resultJson(), const Duration(minutes: 5));
    expect(repo.cachedResult('s1')?.correct, 1);
    expect(repo.cachedHistory(), isNull);
  });
}
