import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/config/remote_config.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/services/notification_service.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';
import 'package:prostuti/features/settings/application/reminder_controller.dart';
import 'package:prostuti/features/settings/application/reminder_time.dart';
import 'package:prostuti/features/settings/presentation/widgets/settings_section.dart';

/// Daily-exam reminder (time saved to the profile, scheduled on device) and
/// the morning-routine nudge (device preference).
class ReminderSettingsScreen extends ConsumerStatefulWidget {
  const ReminderSettingsScreen({super.key});

  @override
  ConsumerState<ReminderSettingsScreen> createState() => _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState extends ConsumerState<ReminderSettingsScreen> {
  bool? _pendingEnabled;
  TimeOfDay? _pendingTime;
  bool _saving = false;
  bool? _permission;

  NotificationService get _notifications => ref.read(notificationServiceProvider);

  Future<bool> _ensurePermission({bool explain = true}) async {
    if (_permission ?? false) return true;
    final granted = await _notifications.requestPermission();
    if (!mounted) return granted;
    setState(() => _permission = granted);
    if (!granted && explain) showInfoSnack(context, context.l10n.settingsPermissionDenied);
    return granted;
  }

  Future<void> _requestPermission() async {
    final granted = await _ensurePermission(explain: false);
    if (!mounted) return;
    final l = context.l10n;
    showInfoSnack(context, granted ? l.settingsPermissionGranted : l.settingsPermissionDenied);
  }

  Future<void> _saveExam({required bool enabled, required TimeOfDay time}) async {
    final l = context.l10n;
    final bangla = context.isBn;
    setState(() {
      _pendingEnabled = enabled;
      _pendingTime = time;
      _saving = true;
    });
    if (enabled) await _ensurePermission();
    try {
      final synced = await saveExamReminder(ref, enabled: enabled, time: time, l: l);
      if (mounted) {
        final message = enabled
            ? l.settingsReminderSaved(formatTimeOfDay(time, bangla: bangla))
            : l.settingsReminderTurnedOff;
        showInfoSnack(context, synced ? message : '$message · ${l.offlineSaved}');
      }
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _pendingEnabled = null;
          _pendingTime = null;
          _saving = false;
        });
      }
    }
  }

  Future<void> _pickTime(TimeOfDay current) async {
    final l = context.l10n;
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      helpText: l.settingsReminderPickTime,
      cancelText: l.cancel,
      confirmText: l.save,
    );
    if (picked == null || !mounted || picked == current) return;
    await _saveExam(enabled: true, time: picked);
  }

  Future<void> _toggleMorning(bool enabled, TimeOfDay time) async {
    final l = context.l10n;
    if (enabled) await _ensurePermission();
    await ref.read(morningRoutineEnabledProvider.notifier).set(enabled: enabled);
    try {
      await ref.read(reminderSchedulerProvider).applyMorningRoutine(enabled: enabled, time: time, l: l);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _sendTest() async {
    final l = context.l10n;
    if (!await _ensurePermission()) return;
    await _notifications.show(
      title: l.settingsTestNotifTitle,
      body: l.settingsTestNotifBody,
      payload: Routes.reminders,
    );
    if (mounted) showInfoSnack(context, l.settingsTestNotifSent);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bangla = context.isBn;
    final profileAsync = ref.watch(currentProfileProvider);
    final profile = profileAsync.value;
    final enabled = _pendingEnabled ?? profile?.reminderEnabled ?? true;
    final time = _pendingTime ?? timeOfDayFromDb(profile?.reminderTime);
    final morning = ref.watch(morningRoutineEnabledProvider);
    final config = ref.watch(remoteConfigProvider).value ?? RemoteConfig.fallback;
    final morningTime = timeOfDayFromDb(config.morningRoutineTime, fallback: const TimeOfDay(hour: 6, minute: 30));

    if (profile == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l.settingsReminders)),
        body: profileAsync.hasError
            ? ErrorView(
                error: profileAsync.error!,
                onRetry: () => unawaited(ref.read(currentProfileProvider.notifier).reload()),
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.settingsReminders)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl),
        children: [
          _PermissionCard(granted: _permission, onRequest: () => unawaited(_requestPermission())),
          SettingsSection(
            title: l.settingsDailyExamReminder,
            children: [
              SwitchListTile(
                secondary: const SettingsIcon(Icons.alarm_rounded),
                title: Text(l.settingsDailyExamReminder),
                subtitle: Text(l.settingsDailyExamReminderHint),
                value: enabled,
                onChanged: _saving ? null : (v) => unawaited(_saveExam(enabled: v, time: time)),
              ),
              ListTile(
                enabled: enabled && !_saving,
                leading: const SettingsIcon(Icons.schedule_rounded),
                title: Text(l.settingsReminderTime),
                subtitle: Text(l.settingsReminderEveryDay(formatTimeOfDay(time, bangla: bangla))),
                trailing: _saving
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(
                        formatTimeOfDay(time, bangla: bangla),
                        style: theme.textTheme.titleMedium?.copyWith(color: enabled ? scheme.primary : null),
                      ),
                onTap: () => unawaited(_pickTime(time)),
              ),
            ],
          ),
          SettingsSection(
            title: l.settingsMorningRoutine,
            children: [
              SwitchListTile(
                secondary: const SettingsIcon(Icons.wb_sunny_outlined),
                title: Text(l.settingsMorningRoutine),
                subtitle: Text(l.settingsMorningRoutineHint(formatTimeOfDay(morningTime, bangla: bangla))),
                value: morning,
                onChanged: (v) => unawaited(_toggleMorning(v, morningTime)),
              ),
            ],
          ),
          Gap.h24,
          OutlinedButton.icon(
            onPressed: () => unawaited(_sendTest()),
            icon: const Icon(Icons.notifications_active_outlined),
            label: Text(l.settingsTestNotification),
          ),
          Gap.h16,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: scheme.onSurfaceVariant),
              Gap.w8,
              Expanded(
                child: Text(
                  l.settingsReminderFootnote,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.granted, required this.onRequest});

  final bool? granted;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ok = granted ?? false;
    return Card(
      color: (ok ? scheme.primaryContainer : scheme.secondaryContainer).withValues(alpha: 0.6),
      child: Padding(
        padding: Gap.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ok ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
                  color: ok ? scheme.onPrimaryContainer : scheme.onSecondaryContainer,
                ),
                Gap.w8,
                Expanded(
                  child: Text(
                    ok ? l.settingsPermissionGrantedTitle : l.settingsPermissionTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            Gap.h8,
            Text(l.settingsPermissionBody, style: theme.textTheme.bodySmall),
            if (!ok) ...[
              Gap.h12,
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: onRequest,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: Text(l.settingsPermissionAllow),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
