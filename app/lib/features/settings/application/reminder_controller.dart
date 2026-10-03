import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/config/remote_config.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/services/notification_service.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';
import 'package:prostuti/features/settings/application/reminder_time.dart';

/// Device-local preference: the morning-routine nudge (on by default).
class MorningRoutineNotifier extends Notifier<bool> {
  static const key = 'pref:morning_routine';

  @override
  bool build() {
    final raw = ref.read(cacheStoreProvider).read(key)?.data;
    return raw is! bool || raw;
  }

  Future<void> set({required bool enabled}) {
    state = enabled;
    return ref.read(cacheStoreProvider).write(key, enabled, const Duration(days: 3650));
  }
}

final morningRoutineEnabledProvider = NotifierProvider<MorningRoutineNotifier, bool>(MorningRoutineNotifier.new);

/// Schedules / cancels the two on-device reminders with localized text.
class ReminderScheduler {
  const ReminderScheduler(this._notifications);

  final NotificationService _notifications;

  Future<void> applyExamReminder({required bool enabled, required TimeOfDay time, required AppLocalizations l}) {
    if (!enabled) return _notifications.cancel(NotificationService.reminderId);
    return _notifications.scheduleDaily(
      id: NotificationService.reminderId,
      time: time,
      title: l.settingsReminderNotifTitle,
      body: l.settingsReminderNotifBody,
      payload: Routes.dailyExam,
    );
  }

  Future<void> applyMorningRoutine({required bool enabled, required TimeOfDay time, required AppLocalizations l}) {
    if (!enabled) return _notifications.cancel(NotificationService.morningRoutineId);
    return _notifications.scheduleDaily(
      id: NotificationService.morningRoutineId,
      time: time,
      title: l.settingsMorningNotifTitle,
      body: l.settingsMorningNotifBody,
      payload: Routes.plan,
    );
  }

  Future<void> cancelAll() async {
    await _notifications.cancel(NotificationService.reminderId);
    await _notifications.cancel(NotificationService.morningRoutineId);
  }
}

final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => ReminderScheduler(ref.watch(notificationServiceProvider)),
);

/// (Re)schedules the daily-exam reminder on the device — works offline — and
/// saves it to the profile through the offline queue. Returns true when the
/// profile change already reached the server.
Future<bool> saveExamReminder(
  WidgetRef ref, {
  required bool enabled,
  required TimeOfDay time,
  required AppLocalizations l,
}) async {
  final profileNotifier = ref.read(currentProfileProvider.notifier);
  await ref.read(reminderSchedulerProvider).applyExamReminder(enabled: enabled, time: time, l: l);
  return profileNotifier.saveOfflineFirst({'reminder_enabled': enabled, 'reminder_time': timeOfDayToDb(time)});
}

/// Re-applies both local reminders from the saved profile + preferences.
/// Safe to call on every app start (scheduling the same id replaces it), e.g.
/// from the home screen once the profile has loaded.
Future<void> syncLocalReminders(WidgetRef ref, AppLocalizations l) async {
  final profile = ref.read(currentProfileProvider).value;
  final scheduler = ref.read(reminderSchedulerProvider);
  if (profile == null) return scheduler.cancelAll();
  await scheduler.applyExamReminder(
    enabled: profile.reminderEnabled,
    time: timeOfDayFromDb(profile.reminderTime),
    l: l,
  );
  final config = await ref.read(remoteConfigProvider.future);
  await scheduler.applyMorningRoutine(
    enabled: ref.read(morningRoutineEnabledProvider),
    time: timeOfDayFromDb(config.morningRoutineTime, fallback: const TimeOfDay(hour: 6, minute: 30)),
    l: l,
  );
}
