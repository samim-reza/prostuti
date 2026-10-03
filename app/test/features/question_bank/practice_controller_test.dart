import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:prostuti/core/cache/cache_store.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/question_bank/application/practice_controller.dart';
import 'package:prostuti/features/question_bank/data/offline_pack_store.dart';
import 'package:prostuti/features/question_bank/data/question_bank_models.dart';
import 'package:prostuti/features/question_bank/data/question_bank_repository.dart';

import '../exam/fixtures.dart';

class _MockRepo extends Mock implements QuestionBankRepository;

List<Question> _questions(Iterable<int> ids, {bool withAnswers = false, int subjectId = 7}) => [
  for (final id in ids)
    Question.fromJson({
      ...questionJson(id, subjectId: subjectId, topicId: id.isEven ? 702 : 701),
      if (withAnswers) ...{'correct_index': id % 4, 'explanation': 'ব্যাখ্যা $id'},
    }),
];

void main() {
  late _MockRepo repo;
  late OfflinePackStore packs;
  late ProviderContainer container;

  setUp(() async {
    repo = _MockRepo();
    packs = OfflinePackStore(MemoryPackStorage(), 'u1');
    final cache = await CacheStore.inMemory();
    container = ProviderContainer(
      overrides: [
        questionBankRepositoryProvider.overrideWithValue(repo),
        offlinePackStoreProvider.overrideWith((ref) async => packs),
        currentUserIdProvider.overrideWithValue('u1'),
        cacheStoreProvider.overrideWithValue(cache),
      ],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    addTearDown(ConnectivityService.instance.reportSuccess);

    when(
      () => repo.practiceQuestions(
        subjectId: any(named: 'subjectId'),
        topicId: any(named: 'topicId'),
        sourceId: any(named: 'sourceId'),
        afterId: any(named: 'afterId'),
        unseenOnly: any(named: 'unseenOnly'),
      ),
    ).thenAnswer((inv) async {
      final after = inv.namedArguments[#afterId] as int?;
      return after == null ? _questions(List.generate(20, (i) => i + 1)) : _questions([21, 22, 23, 24, 25]);
    });
  });

  NotifierProvider<PracticeController, PracticeState> watch(PracticeQuery query) {
    final provider = practiceControllerProvider(query);
    container.listen(provider, (_, _) {});
    return provider;
  }

  Future<PracticeState> settle(NotifierProvider<PracticeController, PracticeState> provider) async {
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(Duration.zero);
      final s = container.read(provider);
      if (!s.isLoadingFirst && !s.isLoadingMore) return s;
    }
    return container.read(provider);
  }

  group('online (RPC) mode', () {
    const query = PracticeQuery(subjectId: 7);

    test('loads the first page and prefetches when 3 remain', () async {
      final provider = watch(query);
      var s = await settle(provider);
      expect(s.items, hasLength(20));
      expect(s.hasMore, isTrue);
      expect(s.fromPack, isFalse);

      container.read(provider.notifier).goTo(15);
      s = await settle(provider);
      expect(s.items, hasLength(20), reason: '4 left → no prefetch yet');

      container.read(provider.notifier).goTo(16);
      s = await settle(provider);
      expect(s.items.map((q) => q.id).last, 25);
      expect(s.hasMore, isFalse, reason: 'short page = last page');
      verify(() => repo.practiceQuestions(subjectId: 7, afterId: 20)).called(1);
    });

    test('answers are graded by the server', () async {
      when(() => repo.answer(1, 2))
          .thenAnswer((_) async => const PracticeVerdict(isCorrect: false, correctIndex: 1, explanation: 'কারণ'));
      final provider = watch(query);
      final s0 = await settle(provider);
      await container.read(provider.notifier).answer(s0.items.first, 2);
      final s = container.read(provider);
      final o = s.outcomes[1]!;
      expect(o.correctIndex, 1);
      expect(o.isCorrect, isFalse);
      expect(o.explanation, 'কারণ');
      expect(s.attempted, 1);
      expect(s.correct, 0);

      // A second tap on an answered question is ignored.
      await container.read(provider.notifier).answer(s0.items.first, 1);
      verify(() => repo.answer(1, any())).called(1);
    });

    test("today's live daily-exam question is locked, not an error", () async {
      when(() => repo.answer(any(), any())).thenThrow(const PermissionFailure('question_locked'));
      final provider = watch(query);
      final s0 = await settle(provider);
      await container.read(provider.notifier).answer(s0.items.first, 0);
      expect(container.read(provider).outcomes[1]!.locked, isTrue);
    });

    test('other failures roll back and rethrow', () async {
      when(() => repo.answer(any(), any())).thenThrow(const RateLimitFailure());
      final provider = watch(query);
      final s0 = await settle(provider);
      await expectLater(container.read(provider.notifier).answer(s0.items.first, 0), throwsA(isA<RateLimitFailure>()));
      expect(container.read(provider).outcomes, isEmpty);
    });

    test('reveal shows the answer without grading', () async {
      when(() => repo.reveal(1)).thenAnswer((_) async => const PracticeVerdict(correctIndex: 3));
      final provider = watch(query);
      final s0 = await settle(provider);
      await container.read(provider.notifier).reveal(s0.items.first);
      final s = container.read(provider);
      expect(s.outcomes[1]!.revealed, isTrue);
      expect(s.outcomes[1]!.isCorrect, isNull);
      expect(s.attempted, 0);
    });

    test('offline without a pack asks for a download', () async {
      ConnectivityService.instance.reportFailure();
      final provider = watch(query);
      final s = await settle(provider);
      expect(s.needsPack, isTrue);
      expect(s.items, isEmpty);
    });
  });

  group('offline pack mode', () {
    test('a downloaded pack starts instantly and grades on device', () async {
      await packs.save(7, _questions([1, 2, 3, 4], withAnswers: true));
      final provider = watch(const PracticeQuery(subjectId: 7));
      final s0 = await settle(provider);
      expect(s0.fromPack, isTrue);
      expect(s0.hasMore, isFalse);
      expect(s0.items.map((q) => q.id), [1, 2, 3, 4]);

      // Question 3 → correct index 3.
      await container.read(provider.notifier).answer(s0.items[2], 3);
      final s = container.read(provider);
      expect(s.outcomes[3]!.isCorrect, isTrue);
      expect(s.outcomes[3]!.explanation, 'ব্যাখ্যা 3');
      expect(s.correct, 1);
      verifyNever(() => repo.answer(any(), any()));
      verifyNever(
        () => repo.practiceQuestions(
          subjectId: any(named: 'subjectId'),
          topicId: any(named: 'topicId'),
          sourceId: any(named: 'sourceId'),
          afterId: any(named: 'afterId'),
          unseenOnly: any(named: 'unseenOnly'),
        ),
      );

      // Buffered for sync_practice_attempts with a client id.
      final buffered = packs.buffered();
      expect(buffered, hasLength(1));
      expect(buffered.single.questionId, 3);
      expect(buffered.single.selectedIndex, 3);
      expect(buffered.single.clientId, hasLength(36));
      expect(packs.seen(), {3});
    });

    test('works offline, filters by topic and supports "new questions only"', () async {
      ConnectivityService.instance.reportFailure();
      await packs.save(7, _questions([1, 2, 3, 4], withAnswers: true));
      await packs.markSeen([2]);
      final provider = watch(const PracticeQuery(topicId: 702));
      final s0 = await settle(provider);
      expect(s0.fromPack, isTrue);
      expect(s0.items.map((q) => q.id), [2, 4]);

      await container.read(provider.notifier).setUnseenOnly(true);
      final s1 = await settle(provider);
      expect(s1.items.map((q) => q.id), [4]);
    });

    test('"practise all" uses packs only when offline', () async {
      await packs.save(7, _questions([1, 2], withAnswers: true));
      final provider = watch(const PracticeQuery());
      expect((await settle(provider)).fromPack, isFalse);

      ConnectivityService.instance.reportFailure();
      container.invalidate(provider);
      final offline = await settle(provider);
      expect(offline.fromPack, isTrue);
      expect(offline.items.map((q) => q.id), [1, 2]);
    });
  });
}
