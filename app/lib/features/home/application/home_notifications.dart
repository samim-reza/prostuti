import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/cache/cache_store.dart';
import 'package:prostuti/core/config/app_settings.dart';
import 'package:prostuti/core/config/remote_config.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/services/notification_service.dart';
import 'package:prostuti/features/profile/data/profile.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';
import 'package:prostuti/features/study_plan/application/plan_providers.dart';

/// Which local notifications should exist. `null` time → cancel it.
/// [morningKnown] is false while we don't yet know whether a plan exists
/// (then the morning notification is left as it is).
@immutable
class HomeNotificationPlan {
  const HomeNotificationPlan({
    required this.userId,
    required this.locale,
    this.reminderAt,
    this.morningAt,
    this.morningKnown = true,
  });

  final String userId;
  final String locale;
  final TimeOfDay? reminderAt;
  final TimeOfDay? morningAt;
  final bool morningKnown;

  @override
  bool operator ==(Object other) =>
      other is HomeNotificationPlan &&
      other.userId == userId &&
      other.locale == locale &&
      other.reminderAt == reminderAt &&
      other.morningAt == morningAt &&
      other.morningKnown == morningKnown;

  @override
  int get hashCode => Object.hash(userId, locale, reminderAt, morningAt, morningKnown);
}

/// Pure decision (unit tested): the daily exam reminder follows the user's
/// reminder settings; the morning routine nudge needs an active plan and the
/// `routine` notification category.
HomeNotificationPlan planHomeNotifications({
  required Profile profile,
  required String morningRoutineTime,
  required bool? hasPlan,
  required String locale,
}) {
  final examOn = profile.reminderEnabled && profile.notificationSettings['exam'] != false;
  final routineOn = profile.notificationSettings['routine'] != false;
  return HomeNotificationPlan(
    userId: profile.id,
    locale: locale,
    reminderAt: examOn ? parseTimeOfDay(profile.reminderTime) : null,
    morningAt: routineOn && (hasPlan ?? false)
        ? parseTimeOfDay(morningRoutineTime, fallback: const TimeOfDay(hour: 6, minute: 30))
        : null,
    morningKnown: hasPlan != null,
  );
}

/// Recomputed whenever an input changes; `==` keeps listeners quiet otherwise.
final homeNotificationPlanProvider = Provider<HomeNotificationPlan?>((ref) {
  final profile = ref.watch(currentProfileProvider.select((p) => p.value));
  if (profile == null || !profile.isOnboarded) return null;
  final morning = ref.watch(remoteConfigProvider.select((c) => c.value?.morningRoutineTime)) ?? '06:30';
  final hasPlan = ref.watch(todayRoutineProvider.select((r) => r.value?.hasPlan));
  final locale = ref.watch(appSettingsProvider.select((s) => s.locale.languageCode));
  return planHomeNotifications(profile: profile, morningRoutineTime: morning, hasPlan: hasPlan, locale: locale);
});

/// Notification copy, resolved from l10n by the caller.
typedef HomeNotificationTexts = ({String reminderTitle, String reminderBody, String morningTitle, String morningBody});

/// Applies a [HomeNotificationPlan] to the OS scheduler. Idempotent: same id
/// → the previous schedule is replaced. Asks for permission once per install.
class HomeNotificationScheduler {
  HomeNotificationScheduler(this._service, this._store);

  final NotificationService _service;
  final CacheStore _store;

  static const permissionAskedKey = 'home:notif_permission_asked';

  /// Last plan applied in this app run — Home can be rebuilt many times, but
  /// the OS schedule only changes when the plan does.
  static HomeNotificationPlan? _applied;

  @visibleForTesting
  static void resetForTest() => _applied = null;

  Future<void> apply(HomeNotificationPlan plan, HomeNotificationTexts texts) async {
    if (kIsWeb || plan == _applied) return;
    _applied = plan;
    try {
      await _service.init();
      if (_store.read(permissionAskedKey) == null) {
        await _store.write(permissionAskedKey, true, const Duration(days: 3650));
        await _service.requestPermission();
      }
      if (plan.reminderAt != null) {
        await _service.scheduleDaily(
          id: NotificationService.reminderId,
          time: plan.reminderAt!,
          title: texts.reminderTitle,
          body: texts.reminderBody,
          payload: Routes.dailyExam,
        );
      } else {
        await _service.cancel(NotificationService.reminderId);
      }
      if (plan.morningKnown) {
        if (plan.morningAt != null) {
          await _service.scheduleDaily(
            id: NotificationService.morningRoutineId,
            time: plan.morningAt!,
            title: texts.morningTitle,
            body: texts.morningBody,
            payload: Routes.plan,
          );
        } else {
          await _service.cancel(NotificationService.morningRoutineId);
        }
      }
    } on Object catch (e) {
      // Notifications are best-effort (plugin missing, permission denied…).
      _applied = null;
      debugPrint('Home notifications not scheduled: $e');
    }
  }
}
