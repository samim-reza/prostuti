import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:prostuti/core/config/app_settings.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/offline/offline_queue.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';
import 'package:prostuti/features/study_plan/application/swr_notifier.dart';
import 'package:prostuti/features/study_plan/data/plan_models.dart';
import 'package:prostuti/features/study_plan/data/readiness_models.dart';
import 'package:prostuti/features/study_plan/data/study_plan_repository.dart';

// -----------------------------------------------------------------------------
// Check-offs waiting in the offline queue ("dayId:key"), so the UI can show a
// pending-sync clock and re-apply them on top of data fetched/cached before.
// -----------------------------------------------------------------------------
class PendingPlanItemsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    final queue = OfflineQueue.instance;
    void sync() {
      if (ref.mounted) state = _read();
    }

    queue.pendingCount.addListener(sync);
    ref.onDispose(() => queue.pendingCount.removeListener(sync));
    return _read();
  }

  static String keyOf(int dayId, String itemKey) => '$dayId:$itemKey';

  Set<String> _read() => {
    for (final op in OfflineQueue.instance.pendingOf(StudyPlanRepository.completeItemOp))
      keyOf((op.payload['day_id'] as num?)?.toInt() ?? -1, '${op.payload['key']}'),
  };
}

final pendingPlanItemsProvider = NotifierProvider<PendingPlanItemsNotifier, Set<String>>(PendingPlanItemsNotifier.new);

/// Re-applies queued (not yet synced) check-offs to a day from the server/cache.
PlanDay applyPendingCompletions(PlanDay day, Set<String> pending) {
  if (pending.isEmpty) return day;
  var out = day;
  for (final item in day.items) {
    if (!item.done && pending.contains(PendingPlanItemsNotifier.keyOf(day.id, item.key))) {
      out = setItemDone(out, item.key);
    }
  }
  return out;
}

// -----------------------------------------------------------------------------
// Today's routine (Home + plan screens)
// -----------------------------------------------------------------------------
class TodayRoutineNotifier extends SwrNotifier<TodayRoutine> {
  final _inFlight = <String>{};

  StudyPlanRepository get _repo => ref.read(studyPlanRepositoryProvider);

  TodayRoutine _withPending(TodayRoutine r) {
    final today = r.today;
    if (today == null) return r;
    return r.withToday(applyPendingCompletions(today, ref.read(pendingPlanItemsProvider)));
  }

  @override
  Peeked<TodayRoutine>? peek() {
    final p = _repo.peekTodayRoutine();
    return p == null ? null : (value: _withPending(p.value), fresh: p.fresh);
  }

  @override
  Future<TodayRoutine> load({bool force = false}) async => _withPending(await _repo.todayRoutine(force: force));

  /// Optimistically ticks [item] off and sends it through the offline queue.
  /// Returns true when it synced immediately, false when it was queued.
  /// Rapid double taps on the same item are ignored while one is in flight.
  Future<bool> completeItem(PlanItem item) async {
    final day = state.value?.today;
    if (day == null || item.done || !item.canComplete || !_inFlight.add(item.key)) return false;
    final optimistic = setItemDone(day, item.key);
    _setToday(optimistic);
    try {
      final ran = await _repo.completeItem(day.id, item.key);
      if (ran && ref.mounted) {
        // The streak may have moved; refresh it quietly.
        unawaited(ref.read(currentProfileProvider.notifier).reload().catchError((Object _) {}));
      }
      unawaited(_repo.cacheDay(optimistic));
      return ran;
    } on Object {
      if (ref.mounted) {
        final current = state.value?.today;
        if (current != null && current.id == day.id) _setToday(setItemDone(current, item.key, done: false));
      }
      rethrow;
    } finally {
      _inFlight.remove(item.key);
    }
  }

  /// Replaces today's day with a fresher copy (e.g. from the day screen).
  /// Keeps weak topics, which only `get_today_routine` returns.
  void syncDay(PlanDay updated) {
    final current = state.value?.today;
    if (current == null || current.id != updated.id) return;
    _setToday(updated.copyWith(weakTopics: updated.weakTopics.isEmpty ? current.weakTopics : updated.weakTopics));
  }

  void _setToday(PlanDay day) {
    final routine = state.value;
    if (routine == null) return;
    final next = routine.withToday(day);
    state = AsyncData(next);
    unawaited(_repo.cacheTodayRoutine(next));
  }
}

final todayRoutineProvider = AsyncNotifierProvider<TodayRoutineNotifier, TodayRoutine>(TodayRoutineNotifier.new);

// -----------------------------------------------------------------------------
// Plan overview
// -----------------------------------------------------------------------------
class PlanOverviewNotifier extends SwrNotifier<PlanOverview> {
  StudyPlanRepository get _repo => ref.read(studyPlanRepositoryProvider);

  @override
  Peeked<PlanOverview>? peek() => _repo.peekOverview();

  @override
  Future<PlanOverview> load({bool force = false}) => _repo.overview(force: force);
}

final planOverviewProvider = AsyncNotifierProvider<PlanOverviewNotifier, PlanOverview>(PlanOverviewNotifier.new);

// -----------------------------------------------------------------------------
// Readiness (Home card, progress screen, onboarding result)
// -----------------------------------------------------------------------------
class ReadinessNotifier extends SwrNotifier<Readiness> {
  StudyPlanRepository get _repo => ref.read(studyPlanRepositoryProvider);

  @override
  Peeked<Readiness>? peek() => _repo.peekReadiness();

  @override
  Future<Readiness> load({bool force = false}) => _repo.readiness(force: force);
}

final readinessProvider = AsyncNotifierProvider<ReadinessNotifier, Readiness>(ReadinessNotifier.new);

// -----------------------------------------------------------------------------
// A single visible day (null → locked by RLS or missing). Cached for offline.
// -----------------------------------------------------------------------------
class PlanDayNotifier extends AsyncNotifier<PlanDay?> {
  PlanDayNotifier(this.dayId);

  final int dayId;
  final _inFlight = <String>{};

  StudyPlanRepository get _repo => ref.read(studyPlanRepositoryProvider);

  PlanDay? _decorate(PlanDay? day) {
    if (day == null) return null;
    // Today's row from the routine carries weak topics; reuse them.
    final today = ref.read(todayRoutineProvider).value?.today;
    final withTopics = today != null && today.id == day.id && day.weakTopics.isEmpty
        ? day.copyWith(weakTopics: today.weakTopics)
        : day;
    return applyPendingCompletions(withTopics, ref.read(pendingPlanItemsProvider));
  }

  @override
  FutureOr<PlanDay?> build() {
    final cached = _repo.peekDay(dayId);
    if (cached != null) {
      if (!cached.fresh) unawaited(Future.microtask(() => refresh().catchError((Object _) {})));
      return _decorate(cached.value);
    }
    return _repo.day(dayId).then(_decorate);
  }

  Future<void> refresh() async {
    final day = _decorate(await _repo.day(dayId, force: true));
    if (ref.mounted) state = AsyncData(day);
  }

  /// Same contract as [TodayRoutineNotifier.completeItem].
  Future<bool> completeItem(PlanItem item) async {
    final day = state.value;
    if (day == null || item.done || !item.canComplete || !_inFlight.add(item.key)) return false;
    final optimistic = setItemDone(day, item.key);
    state = AsyncData(optimistic);
    ref.read(todayRoutineProvider.notifier).syncDay(optimistic);
    try {
      final ran = await _repo.completeItem(day.id, item.key);
      unawaited(_repo.cacheDay(optimistic));
      if (ran && ref.mounted) {
        unawaited(ref.read(currentProfileProvider.notifier).reload().catchError((Object _) {}));
      }
      return ran;
    } on Object {
      if (ref.mounted && state.value != null) {
        final reverted = setItemDone(state.value!, item.key, done: false);
        state = AsyncData(reverted);
        ref.read(todayRoutineProvider.notifier).syncDay(reverted);
      }
      rethrow;
    } finally {
      _inFlight.remove(item.key);
    }
  }
}

final planDayProvider = AsyncNotifierProvider.autoDispose.family<PlanDayNotifier, PlanDay?, int>(PlanDayNotifier.new);

// -----------------------------------------------------------------------------
// Plan generation (onboarding result, plan screen, Home CTA)
// -----------------------------------------------------------------------------
@immutable
class PlanGenerationState {
  const PlanGenerationState({this.running = false, this.error, this.succeeded = false});

  static const idle = PlanGenerationState();

  final bool running;
  final AppFailure? error;
  final bool succeeded;
}

class PlanGenerationNotifier extends Notifier<PlanGenerationState> {
  @override
  PlanGenerationState build() => PlanGenerationState.idle;

  /// Generates (or regenerates) the plan; returns true on success. Never
  /// throws — the failure is exposed in [state] so callers can let the user
  /// continue without a plan.
  Future<bool> generate({String mode = 'create'}) async {
    if (state.running) return false;
    state = const PlanGenerationState(running: true);
    try {
      final locale = ref.read(appSettingsProvider).locale.languageCode == 'en' ? 'en' : 'bn';
      await ref.read(studyPlanRepositoryProvider).generatePlan(mode: mode, locale: locale);
      await refreshPlanData(ref.read, quiet: true);
      if (!ref.mounted) return true;
      state = const PlanGenerationState(succeeded: true);
      return true;
    } on Object catch (e) {
      if (ref.mounted) state = PlanGenerationState(error: AppFailure.from(e));
      return false;
    }
  }

  void reset() => state = PlanGenerationState.idle;
}

final planGenerationProvider = NotifierProvider<PlanGenerationNotifier, PlanGenerationState>(
  PlanGenerationNotifier.new,
);

/// `ref.read` of either a `Ref` or a `WidgetRef`.
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

/// Refreshes routine + overview + readiness in parallel. With [quiet] the
/// errors are swallowed (background refresh); otherwise the first error is
/// rethrown (after all calls settle) for pull-to-refresh feedback.
Future<void> refreshPlanData(ProviderReader read, {bool quiet = false}) async {
  final futures = <Future<void>>[
    read(todayRoutineProvider.notifier).refresh(),
    read(planOverviewProvider.notifier).refresh(),
    read(readinessProvider.notifier).refresh(),
  ];
  if (quiet) {
    await Future.wait(futures.map((f) => f.catchError((Object _) {})));
  } else {
    await Future.wait(futures);
  }
}
