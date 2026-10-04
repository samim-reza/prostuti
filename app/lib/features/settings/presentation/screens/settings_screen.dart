import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/config/app_settings.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/offline/offline_queue.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/profile/data/profile.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';
import 'package:prostuti/features/settings/application/account_actions.dart';
import 'package:prostuti/features/settings/application/reminder_controller.dart';
import 'package:prostuti/features/settings/application/reminder_time.dart';
import 'package:prostuti/features/settings/application/support.dart';
import 'package:prostuti/features/settings/presentation/logout.dart';
import 'package:prostuti/features/settings/presentation/widgets/settings_section.dart';

/// Notification categories stored in `profiles.notification_settings`.
enum NotificationCategory {
  social(Icons.people_alt_outlined),
  dailyNotes(Icons.article_outlined, 'daily_notes'),
  routine(Icons.event_note_outlined),
  exam(Icons.quiz_outlined),
  chat(Icons.chat_bubble_outline_rounded);

  NotificationCategory(this.icon, [this._key]);
  final IconData icon;
  final String? _key;

  String get key => _key ?? name;

  String title(AppLocalizations l) => switch (this) {
    social => l.settingsNotifSocial,
    dailyNotes => l.settingsNotifDailyNotes,
    routine => l.settingsNotifRoutine,
    exam => l.settingsNotifExam,
    chat => l.settingsNotifChat,
  };

  String subtitle(AppLocalizations l) => switch (this) {
    social => l.settingsNotifSocialHint,
    dailyNotes => l.settingsNotifDailyNotesHint,
    routine => l.settingsNotifRoutineHint,
    exam => l.settingsNotifExamHint,
    chat => l.settingsNotifChatHint,
  };
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// Optimistic values while a profile save is in flight.
  Map<String, bool>? _pendingNotif;
  String? _pendingAllow;
  bool _syncing = false;

  /// Offline-first: applied at once, queued when offline (profile updates are
  /// idempotent), reverted with an error if the server rejects it.
  Future<void> _saveProfile(Map<String, dynamic> patch, VoidCallback clearPending) async {
    try {
      final synced = await ref.read(currentProfileProvider.notifier).saveOfflineFirst(patch);
      if (!synced && mounted) showInfoSnack(context, context.l10n.offlineSaved);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(clearPending);
    }
  }

  Future<void> _toggleNotification(NotificationCategory c, bool value, Map<String, bool> current) async {
    final next = {...current, c.key: value};
    setState(() => _pendingNotif = next);
    await _saveProfile({'notification_settings': next}, () {
      if (identical(_pendingNotif, next)) _pendingNotif = null;
    });
  }

  Future<void> _setAllowMessages(String value) async {
    setState(() => _pendingAllow = value);
    await _saveProfile({'allow_messages_from': value}, () {
      if (_pendingAllow == value) _pendingAllow = null;
    });
  }

  Future<void> _setLocale(String code) async {
    await ref.read(appSettingsProvider.notifier).setLocale(Locale(code));
    try {
      // Reminder texts follow the app language (local, works offline).
      await syncLocalReminders(ref, lookupAppLocalizations(Locale(code)));
      await ref.read(currentProfileProvider.notifier).saveOfflineFirst({'locale': code});
    } on Object catch (e) {
      // The device language already changed; the server copy is best-effort.
      debugPrint('locale sync failed: $e');
    }
  }

  Future<void> _clearCache() async {
    final l = context.l10n;
    final ok = await confirmDialog(
      context,
      title: l.settingsClearCacheTitle,
      message: l.settingsClearCacheBody,
      confirmLabel: l.settingsClearCacheConfirm,
    );
    if (!ok || !mounted) return;
    await clearAppCache(ref);
    if (mounted) showInfoSnack(context, l.settingsClearCacheDone);
  }

  Future<void> _requestDeletion(Profile? profile) async {
    final l = context.l10n;
    final ok = await confirmDialog(
      context,
      title: l.settingsDeleteAccountTitle,
      message: l.settingsDeleteAccountBody,
      confirmLabel: l.settingsDeleteAccountConfirm,
      destructive: true,
    );
    if (!ok || !mounted) return;
    final email = ref.read(supportEmailProvider);
    final launched = await launchEmail(
      email,
      subject: l.settingsDeleteMailSubject,
      body: l.settingsDeleteMailBody(profile?.username ?? '', profile?.id ?? ''),
    );
    if (!launched && mounted) {
      await Clipboard.setData(ClipboardData(text: email));
      if (mounted) showInfoSnack(context, l.settingsNoMailApp(email));
    }
  }

  Future<void> _contactSupport() async {
    final l = context.l10n;
    final email = ref.read(supportEmailProvider);
    final launched = await launchEmail(email, subject: l.settingsSupportSubject);
    if (!launched && mounted) {
      await Clipboard.setData(ClipboardData(text: email));
      if (mounted) showInfoSnack(context, l.settingsNoMailApp(email));
    }
  }

  Future<void> _syncNow() async {
    final l = context.l10n;
    if (!ConnectivityService.instance.isOnline) {
      showInfoSnack(context, l.offlineUnavailable);
      return;
    }
    setState(() => _syncing = true);
    try {
      await OfflineQueue.instance.flush();
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
    if (!mounted) return;
    final left = OfflineQueue.instance.pendingCount.value;
    showInfoSnack(context, left == 0 ? l.settingsOfflineSynced : l.settingsOfflinePending(context.n(left)));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = ref.watch(appSettingsProvider);
    final profile = ref.watch(currentProfileProvider).value;
    final notif = _pendingNotif ?? profile?.notificationSettings ?? const <String, bool>{};
    final allow = _pendingAllow ?? profile?.allowMessagesFrom ?? 'friends';
    final pendingSync = ref.watch(pendingSyncCountProvider).value ?? OfflineQueue.instance.pendingCount.value;
    final reminderLabel = profile == null
        ? null
        : profile.reminderEnabled
        ? l.settingsReminderEveryDay(formatTimeOfDay(timeOfDayFromDb(profile.reminderTime), bangla: context.isBn))
        : l.settingsOff;

    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.xxl),
        children: [
          SettingsSection(
            title: l.settingsAppearance,
            children: [
              _ChoiceRow<ThemeMode>(
                icon: Icons.palette_outlined,
                title: l.settingsTheme,
                selected: settings.themeMode,
                onChanged: (m) => unawaited(ref.read(appSettingsProvider.notifier).setThemeMode(m)),
                segments: [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: const Icon(Icons.brightness_auto_rounded),
                    label: Text(l.settingsThemeSystem),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: const Icon(Icons.light_mode_rounded),
                    label: Text(l.settingsThemeLight),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: const Icon(Icons.dark_mode_rounded),
                    label: Text(l.settingsThemeDark),
                  ),
                ],
              ),
              _ChoiceRow<String>(
                icon: Icons.translate_rounded,
                title: l.settingsLanguage,
                selected: settings.locale.languageCode,
                onChanged: (code) => unawaited(_setLocale(code)),
                segments: [
                  ButtonSegment(value: 'bn', label: Text(l.settingsLanguageBangla)),
                  ButtonSegment(value: 'en', label: Text(l.settingsLanguageEnglish)),
                ],
              ),
            ],
          ),
          SettingsSection(
            title: l.settingsNotifications,
            footer: l.settingsNotificationsFooter,
            children: [
              ListTile(
                leading: const SettingsIcon(Icons.alarm_rounded),
                title: Text(l.settingsReminders),
                subtitle: reminderLabel == null ? null : Text(reminderLabel),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => unawaited(context.push(Routes.reminders)),
              ),
              for (final c in NotificationCategory.values)
                SwitchListTile(
                  secondary: SettingsIcon(c.icon),
                  title: Text(c.title(l)),
                  subtitle: Text(c.subtitle(l)),
                  value: notif[c.key] ?? true,
                  onChanged: profile == null ? null : (v) => unawaited(_toggleNotification(c, v, notif)),
                ),
            ],
          ),
          SettingsSection(
            title: l.settingsPrivacy,
            children: [
              _ChoiceRow<String>(
                icon: Icons.mark_chat_unread_outlined,
                title: l.settingsAllowMessages,
                subtitle: l.settingsAllowMessagesHint,
                selected: allow,
                onChanged: profile == null ? null : (v) => unawaited(_setAllowMessages(v)),
                segments: [
                  ButtonSegment(
                    value: 'friends',
                    icon: const Icon(Icons.group_rounded),
                    label: Text(l.settingsAllowFriends),
                  ),
                  ButtonSegment(
                    value: 'everyone',
                    icon: const Icon(Icons.public_rounded),
                    label: Text(l.settingsAllowEveryone),
                  ),
                ],
              ),
              _NavTile(
                icon: Icons.block_rounded,
                title: l.settingsBlockedUsers,
                onTap: () => context.push(Routes.blockedUsers),
              ),
            ],
          ),
          SettingsSection(
            title: l.settingsAccount,
            children: [
              _NavTile(
                icon: Icons.person_outline_rounded,
                title: l.settingsEditProfile,
                onTap: () => context.push(Routes.editProfile),
              ),
              _NavTile(
                icon: Icons.lock_reset_rounded,
                title: l.settingsChangePassword,
                onTap: () => context.push(Routes.changePassword),
              ),
              _NavTile(
                icon: Icons.workspace_premium_outlined,
                title: l.settingsAddons,
                onTap: () => context.push(Routes.addons),
              ),
              ListTile(
                leading: SettingsIcon(Icons.person_remove_outlined, color: scheme.error),
                title: Text(l.settingsDeleteAccount),
                subtitle: Text(l.settingsDeleteAccountHint),
                onTap: () => unawaited(_requestDeletion(profile)),
              ),
            ],
          ),
          SettingsSection(
            title: l.settingsDataAndSupport,
            children: [
              ListTile(
                leading: const SettingsIcon(Icons.cloud_sync_outlined),
                title: Text(l.settingsOfflineData),
                subtitle: Text(
                  pendingSync == 0 ? l.settingsOfflineAllSynced : l.settingsOfflinePending(context.n(pendingSync)),
                ),
                trailing: pendingSync == 0
                    ? Icon(Icons.cloud_done_outlined, color: scheme.primary)
                    : TextButton(
                        onPressed: _syncing ? null : () => unawaited(_syncNow()),
                        child: _syncing
                            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(l.settingsSyncNow),
                      ),
              ),
              ListTile(
                leading: const SettingsIcon(Icons.cleaning_services_outlined),
                title: Text(l.settingsClearCache),
                subtitle: Text(l.settingsClearCacheHint),
                onTap: () => unawaited(_clearCache()),
              ),
              ListTile(
                leading: const SettingsIcon(Icons.support_agent_rounded),
                title: Text(l.settingsContactSupport),
                subtitle: Text(ref.watch(supportEmailProvider)),
                onTap: () => unawaited(_contactSupport()),
              ),
              _NavTile(
                icon: Icons.info_outline_rounded,
                title: l.settingsAbout,
                onTap: () => context.push(Routes.about),
              ),
            ],
          ),
          Gap.h24,
          OutlinedButton.icon(
            onPressed: () => unawaited(confirmAndSignOut(context, ref)),
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.error,
              side: BorderSide(color: scheme.error.withValues(alpha: 0.6)),
            ),
            icon: const Icon(Icons.logout_rounded),
            label: Text(l.settingsLogout),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.icon, required this.title, required this.onTap});

  final IconData icon;
  final String title;
  final Future<Object?> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: SettingsIcon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => unawaited(onTap()),
    );
  }
}

/// Settings row with a segmented choice underneath the title.
class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.icon,
    required this.title,
    required this.selected,
    required this.segments,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final T selected;
  final List<ButtonSegment<T>> segments;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SettingsIcon(icon),
              Gap.w16,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.bodyLarge),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            ],
          ),
          Gap.h12,
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<T>(
              segments: segments,
              selected: {selected},
              showSelectedIcon: false,
              onSelectionChanged: onChanged == null ? null : (s) => onChanged!(s.first),
            ),
          ),
        ],
      ),
    );
  }
}
