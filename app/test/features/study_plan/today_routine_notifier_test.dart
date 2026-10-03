// Fakes rethrow whatever error object the test injects.
// ignore_for_file: only_throw_errors
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/features/profile/data/profile.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';
import 'package:prostuti/features/study_plan/application/plan_providers.dart';
import 'package:prostuti/features/study_plan/data/plan_models.dart';
import 'package:prostuti/features/study_plan/data/study_plan_repository.dart';

class _FakeRepo extends Fake implements StudyPlanRepository {
  _FakeRepo(this.routine);

  TodayRoutine routine;
  Peeked<TodayRoutine>? cached;
  Object? completeError;
  bool completeRuns = true;
  Completer<void>? gate;
  final completed = <String>[];
  TodayRoutine? lastCached;

  @override
  Peeked<TodayRoutine>? peekTodayRoutine() => cached;

  @override
  Future<TodayRoutine> todayRoutine({bool force = false}) async => routine;

  @override
  Future<void> cacheTodayRoutine(TodayRoutine routine) async => lastCached = routine;

  @override
  Future<void> cacheDay(PlanDay day) async {}

  @override
  Future<bool> completeItem(int dayId, String key) async {
    await gate?.future;
    if (completeError != null) throw completeError!;
    completed.add('$dayId:$key');
    return completeRuns;
  }
}

class _FakeProfile extends CurrentProfileNotifier {
  @override
  Future<Profile?> build() async => null;

  @override
  Future<void> reload() async {}
}

TodayRoutine _routine() => TodayRoutine(
  hasPlan: true,
  today: PlanDay(
    id: 1,
    date: DateTime.utc(2026, 10, 4),
    kind: PlanDayKind.study,
    titleBn: 'আজ',
    totalItems: 2,
    items: const [
      PlanItem(key: 'a', type: PlanItemType.read, titleBn: 'ক'),
      PlanItem(key: 'b', type: PlanItemType.practice, titleBn: 'খ'),
    ],
  ),
);

void main() {
  late _FakeRepo repo;
  late ProviderContainer container;

  setUp(() {
    repo = _FakeRepo(_routine());
    container = ProviderContainer(
      overrides: [
        studyPlanRepositoryProvider.overrideWithValue(repo),
        currentUserIdProvider.overrideWithValue('u1'),
        currentProfileProvider.overrideWith(_FakeProfile.new),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<TodayRoutine> load() => container.read(todayRoutineProvider.future);

  test('loads from the network when nothing is cached', () async {
    final r = await load();
    expect(r.today!.items, hasLength(2));
  });

  test('paints cached data synchronously (instant cold start)', () {
    repo.cached = (value: _routine(), fresh: true);
    final value = container.read(todayRoutineProvider);
    expect(value.hasValue, isTrue);
    expect(value.value!.today!.id, 1);
  });

  test('completeItem ticks optimistically, then persists the routine', () async {
    await load();
    repo.gate = Completer<void>();
    final item = container.read(todayRoutineProvider).value!.today!.items.first;
    final future = container.read(todayRoutineProvider.notifier).completeItem(item);

    // Optimistic: visible before the server answers.
    final optimistic = container.read(todayRoutineProvider).value!.today!;
    expect(optimistic.items.first.done, isTrue);
    expect(optimistic.status, PlanDayStatus.partial);

    repo.gate!.complete();
    expect(await future, isTrue);
    expect(repo.completed, ['1:a']);
    expect(repo.lastCached!.today!.items.first.done, isTrue);
  });

  test('queued (offline) completion keeps the optimistic tick', () async {
    await load();
    repo.completeRuns = false;
    final item = container.read(todayRoutineProvider).value!.today!.items.last;
    expect(await container.read(todayRoutineProvider.notifier).completeItem(item), isFalse);
    expect(container.read(todayRoutineProvider).value!.today!.items.last.done, isTrue);
  });

  test('a rejected completion is reverted and rethrown', () async {
    await load();
    repo.completeError = const PermissionFailure('day_not_available');
    final item = container.read(todayRoutineProvider).value!.today!.items.first;
    await expectLater(
      container.read(todayRoutineProvider.notifier).completeItem(item),
      throwsA(isA<PermissionFailure>()),
    );
    final day = container.read(todayRoutineProvider).value!.today!;
    expect(day.items.first.done, isFalse);
    expect(day.status, PlanDayStatus.pending);
  });

  test('double taps on the same item are ignored while in flight', () async {
    await load();
    repo.gate = Completer<void>();
    final notifier = container.read(todayRoutineProvider.notifier);
    final item = container.read(todayRoutineProvider).value!.today!.items.first;
    final first = notifier.completeItem(item);
    final second = await notifier.completeItem(item);
    expect(second, isFalse);
    repo.gate!.complete();
    await first;
    expect(repo.completed, ['1:a']);
  });

  test('syncDay replaces today but keeps weak topics', () async {
    repo.routine = TodayRoutine(
      hasPlan: true,
      today: _routine().today!.copyWith(
        weakTopics: const [WeakTopic(topicId: 9, nameBn: 'দুর্বল', nameEn: 'Weak')],
      ),
    );
    await load();
    final updated = setItemDone(_routine().today!, 'b');
    container.read(todayRoutineProvider.notifier).syncDay(updated);
    final day = container.read(todayRoutineProvider).value!.today!;
    expect(day.items.last.done, isTrue);
    expect(day.weakTopics.single.topicId, 9);
  });
}
