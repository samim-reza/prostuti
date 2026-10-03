import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/config/app_settings.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/offline/offline_queue.dart';
import 'package:prostuti/features/settings/application/reminder_controller.dart';

/// Clears every cached response while keeping device preferences (theme,
/// language, morning-routine toggle) that live in the same box.
Future<void> clearAppCache(WidgetRef ref) async {
  final cache = ref.read(cacheStoreProvider);
  final settings = ref.read(appSettingsProvider);
  final settingsNotifier = ref.read(appSettingsProvider.notifier);
  final morning = ref.read(morningRoutineEnabledProvider);
  final morningNotifier = ref.read(morningRoutineEnabledProvider.notifier);
  await cache.clear();
  await settingsNotifier.setThemeMode(settings.themeMode); // re-persists theme + locale
  await morningNotifier.set(enabled: morning);
}

/// Signs out: stops this account's local reminders, syncs (then drops) queued
/// offline edits, wipes cached data (keeping theme/language) and ends the
/// session. The router redirects to the welcome
/// screen by itself.
Future<void> signOut(WidgetRef ref) async {
  // Read everything up-front: the calling widget may be disposed as soon as
  // the auth state flips.
  final client = ref.read(supabaseProvider);
  final scheduler = ref.read(reminderSchedulerProvider);
  final cache = ref.read(cacheStoreProvider);
  final settings = ref.read(appSettingsProvider);
  final settingsNotifier = ref.read(appSettingsProvider.notifier);

  try {
    await scheduler.cancelAll();
  } on Object catch (e) {
    debugPrint('cancel reminders failed: $e');
  }
  // Last chance to sync this account's offline edits; whatever is left must
  // not replay under the next account that signs in on this device.
  final queue = OfflineQueue.instance;
  try {
    if (ConnectivityService.instance.isOnline) await queue.flush();
    await queue.clear();
  } on Object catch (e) {
    debugPrint('offline queue cleanup failed: $e');
  }
  await cache.clear();
  await settingsNotifier.setThemeMode(settings.themeMode);
  try {
    await client.auth.signOut();
  } on Object catch (e) {
    // The local session is removed before the network call, so the user is
    // signed out on this device even if revoking the token fails.
    debugPrint('signOut: $e');
  }
}
