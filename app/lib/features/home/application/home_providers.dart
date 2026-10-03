import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/config/remote_config.dart';
import 'package:prostuti/core/utils/bd_time.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:prostuti/features/home/application/home_helpers.dart';
import 'package:prostuti/features/home/data/home_models.dart';
import 'package:prostuti/features/home/data/home_repository.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';
import 'package:prostuti/features/study_plan/application/plan_providers.dart';
import 'package:prostuti/features/study_plan/application/swr_notifier.dart';
import 'package:prostuti/features/study_plan/data/study_plan_repository.dart' show Peeked;

class NotesDigestNotifier extends SwrNotifier<NotesDigest> {
  HomeRepository get _repo => ref.read(homeRepositoryProvider);

  @override
  Peeked<NotesDigest>? peek() => _repo.peekNotes();

  @override
  Future<NotesDigest> load({bool force = false}) => _repo.notes(force: force);
}

final notesDigestProvider = AsyncNotifierProvider<NotesDigestNotifier, NotesDigest>(NotesDigestNotifier.new);

class TrialStatusNotifier extends SwrNotifier<TrialStatus> {
  HomeRepository get _repo => ref.read(homeRepositoryProvider);

  @override
  Peeked<TrialStatus>? peek() => _repo.peekTrial();

  @override
  Future<TrialStatus> load({bool force = false}) => _repo.trial(force: force);
}

final trialStatusProvider = AsyncNotifierProvider<TrialStatusNotifier, TrialStatus>(TrialStatusNotifier.new);

/// The exam the countdown card counts down to (null while unknown).
final targetScheduleProvider = Provider<ExamSchedule?>((ref) {
  final schedules = ref.watch(examSchedulesProvider.select((s) => s.value));
  if (schedules == null) return null;
  final targetId = ref.watch(currentProfileProvider.select((p) => p.value?.targetScheduleId));
  final targetExams = ref.watch(currentProfileProvider.select((p) => p.value?.targetExams.join(',') ?? 'bcs'));
  final defaultId = ref.watch(remoteConfigProvider.select((c) => c.value?.defaultScheduleId));
  return resolveTargetSchedule(
    schedules,
    targetId: targetId,
    defaultId: defaultId,
    targetExams: targetExams.split(',').where((e) => e.isNotEmpty).toList(),
  );
});

/// Pull-to-refresh: everything on Home in parallel. Returns the first error
/// (if any) after all calls settle, so one failure doesn't hide the rest.
Future<Object?> refreshHome(ProviderReader read) async {
  Object? firstError;
  Future<void> guarded(Future<void> f) async {
    try {
      await f;
    } on Object catch (e) {
      firstError ??= e;
    }
  }

  await Future.wait([
    guarded(read(currentProfileProvider.notifier).reload()),
    guarded(read(todayRoutineProvider.notifier).refresh()),
    guarded(read(readinessProvider.notifier).refresh()),
    guarded(read(notesDigestProvider.notifier).refresh()),
    guarded(read(trialStatusProvider.notifier).refresh()),
  ]);
  return firstError;
}

/// Today's date in Bangladesh, exposed for widgets (overridable in tests).
final bdTodayProvider = Provider<DateTime>((ref) => BdTime.today());
