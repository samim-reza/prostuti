import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/features/exam/application/exam_session_controller.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/exam/data/exam_repository.dart';

import 'fixtures.dart';

class _MockRepo extends Mock implements ExamRepository;

class _FakeSession extends Fake implements ExamSession;

void main() {
  setUpAll(() => registerFallbackValue(_FakeSession()));

  late _MockRepo repo;
  late ProviderContainer container;
  final provider = examSessionControllerProvider('s1');

  setUp(() {
    repo = _MockRepo();
    when(() => repo.loadSession('s1')).thenAnswer((_) async => session());
    when(() => repo.savedAnswers('s1')).thenReturn({101: 1, 999: 0, 102: 9});
    when(() => repo.savedFlags('s1')).thenReturn({103});
    when(() => repo.isSubmissionPending('s1')).thenReturn(false);
    when(() => repo.saveAnswers(any(), any())).thenAnswer((_) async {});
    when(() => repo.saveFlags(any(), any())).thenAnswer((_) async {});
    container = ProviderContainer(overrides: [examRepositoryProvider.overrideWithValue(repo)], retry: (_, _) => null);
    addTearDown(container.dispose);
    container.listen(provider, (_, _) {});
  });

  Future<ExamTakingState> loaded() => container.read(provider.future);

  test('resumes saved answers and flags, dropping invalid ones', () async {
    final s = await loaded();
    expect(s.sheet.answers, {101: 1});
    expect(s.sheet.flagged, {103});
    expect(s.phase, SubmitPhase.idle);
  });

  test('a queued submission re-opens in the queued state', () async {
    when(() => repo.isSubmissionPending('s1')).thenReturn(true);
    container.invalidate(provider);
    final s = await loaded();
    expect(s.phase, SubmitPhase.queued);
    expect(s.isLocked, isTrue);
  });

  test('answers are persisted once, 300 ms after the last change', () async {
    await loaded();
    container.read(provider.notifier)
      ..select(102, 0)
      ..select(102, 3)
      ..toggleFlag(101);
    expect(container.read(provider).value!.sheet.answers, {101: 1, 102: 3});
    verifyNever(() => repo.saveAnswers(any(), any()));
    await Future<void>.delayed(const Duration(milliseconds: 350));
    verify(() => repo.saveAnswers('s1', {101: 1, 102: 3})).called(1);
    verify(() => repo.saveFlags('s1', {103, 101})).called(1);
  });

  test('submit sends the answer sheet once and ignores double taps', () async {
    await loaded();
    final completer = Completer<ExamSubmitOutcome>();
    when(() => repo.submitOrQueue(any(), any())).thenAnswer((_) => completer.future);
    final notifier = container.read(provider.notifier);
    final first = notifier.submit();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(provider).value!.isSubmitting, isTrue);
    final second = await notifier.submit();
    expect(second, isNull);

    final result = ExamResult.fromJson(resultJson());
    completer.complete(ExamSubmitOutcome(result));
    expect(await first, same(result));
    expect(container.read(provider).value!.phase, SubmitPhase.done);
    verify(() => repo.submitOrQueue(any(), {101: 1})).called(1);

    // After completion, submit returns the stored result without a new call.
    expect(await notifier.submit(), same(result));
    verifyNever(() => repo.submitOrQueue(any(), any()));
  });

  test('answers are locked while submitting and after', () async {
    await loaded();
    when(() => repo.submitOrQueue(any(), any())).thenAnswer((_) async => const ExamSubmitOutcome(null));
    final notifier = container.read(provider.notifier);
    await notifier.submit();
    notifier.select(102, 1);
    expect(container.read(provider).value!.sheet.selectedFor(102), isNull);
  });

  test('offline submit is queued, then picked up when the outbox drains', () async {
    await loaded();
    when(() => repo.submitOrQueue(any(), any())).thenAnswer((_) async => const ExamSubmitOutcome(null));
    final notifier = container.read(provider.notifier);
    expect(await notifier.submit(), isNull);
    expect(container.read(provider).value!.phase, SubmitPhase.queued);

    // Still pending → nothing to show yet.
    when(() => repo.isSubmissionPending('s1')).thenReturn(true);
    expect(notifier.checkQueued(), isNull);

    // Flushed: the queue handler stored the result on device.
    final result = ExamResult.fromJson(resultJson());
    when(() => repo.isSubmissionPending('s1')).thenReturn(false);
    when(() => repo.cachedResult('s1')).thenReturn(result);
    expect(notifier.checkQueued(), same(result));
    expect(container.read(provider).value!.phase, SubmitPhase.done);
  });

  test('a server error leaves the exam retryable', () async {
    await loaded();
    when(() => repo.submitOrQueue(any(), any())).thenThrow(const ServerFailure('session_expired'));
    final notifier = container.read(provider.notifier);
    expect(await notifier.submit(), isNull);
    final s = container.read(provider).value!;
    expect(s.phase, SubmitPhase.failed);
    expect(s.error?.code, 'session_expired');
    expect(s.isLocked, isFalse);

    final result = ExamResult.fromJson(resultJson());
    when(() => repo.submitOrQueue(any(), any())).thenAnswer((_) async => ExamSubmitOutcome(result));
    expect(await notifier.submit(), same(result));
  });

  test('a missing session surfaces NotFoundFailure', () async {
    when(() => repo.loadSession('s1')).thenThrow(const NotFoundFailure('session_not_found'));
    container.invalidate(provider);
    await expectLater(loaded(), throwsA(isA<NotFoundFailure>()));
  });
}
