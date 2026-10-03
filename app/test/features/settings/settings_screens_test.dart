import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:prostuti/core/cache/cache_store.dart';
import 'package:prostuti/core/config/remote_config.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/theme/app_theme.dart';
import 'package:prostuti/features/profile/data/profile.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';
import 'package:prostuti/features/settings/application/support.dart';
import 'package:prostuti/features/settings/presentation/screens/about_screen.dart';
import 'package:prostuti/features/settings/presentation/screens/reminder_settings_screen.dart';
import 'package:prostuti/features/settings/presentation/screens/settings_screen.dart';

class _FakeProfile extends CurrentProfileNotifier {
  @override
  Future<Profile?> build() async =>
      const Profile(id: 'u1', username: 'qa_rahim', reminderTime: '21:30', notificationSettings: {'chat': false});
}

late CacheStore _store;

Widget _host(Widget child, {Locale locale = const Locale('bn'), bool dark = false}) => ProviderScope(
  overrides: [
    cacheStoreProvider.overrideWithValue(_store),
    currentProfileProvider.overrideWith(_FakeProfile.new),
    remoteConfigProvider.overrideWith((ref) async => RemoteConfig.fallback),
    packageInfoProvider.overrideWith(
      (ref) async =>
          PackageInfo(appName: 'Prostuti', packageName: 'io.prostuti.app', version: '1.0.0', buildNumber: '7'),
    ),
  ],
  child: MaterialApp(
    locale: locale,
    theme: dark ? AppTheme.dark() : AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  ),
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('bn');
    await initializeDateFormatting('en');
    _store = await CacheStore.inMemory();
  });

  for (final locale in const [Locale('bn'), Locale('en')]) {
    testWidgets('settings screen renders every section (${locale.languageCode})', (tester) async {
      await tester.pumpWidget(_host(const SettingsScreen(), locale: locale));
      await tester.pumpAndSettle();
      final l = lookupAppLocalizations(locale);
      expect(find.text(l.settingsTheme), findsOneWidget);
      expect(find.text(l.settingsLanguage), findsOneWidget);
      // Saved reminder time is shown in the notifications section.
      expect(
        find.text(l.settingsReminderEveryDay(locale.languageCode == 'bn' ? 'রাত ৯:৩০' : '9:30 PM')),
        findsOneWidget,
      );
      // Notification switches reflect profiles.notification_settings.
      final chat = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, l.settingsNotifChat));
      expect(chat.value, isFalse);
      await tester.scrollUntilVisible(find.text(l.settingsOfflineData), 300);
      expect(find.text(l.settingsOfflineAllSynced), findsOneWidget);
      await tester.scrollUntilVisible(find.text(l.settingsLogout), 300);
    });
  }

  testWidgets('theme choice is applied and persisted', (tester) async {
    await tester.pumpWidget(_host(const SettingsScreen(), locale: const Locale('en')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect((_store.read('app_settings')!.data! as Map)['theme'], 'dark');
  });

  testWidgets('reminder screen shows saved time and morning routine', (tester) async {
    await tester.pumpWidget(_host(const ReminderSettingsScreen(), dark: true));
    await tester.pumpAndSettle();
    final l = lookupAppLocalizations(const Locale('bn'));
    expect(find.text('রাত ৯:৩০'), findsOneWidget);
    expect(find.text(l.settingsMorningRoutineHint('সকাল ৬:৩০')), findsOneWidget);
    expect(find.text(l.settingsTestNotification), findsOneWidget);
  });

  testWidgets('about screen lists sources, version and security notice', (tester) async {
    await tester.pumpWidget(_host(const AboutScreen()));
    await tester.pumpAndSettle();
    final l = lookupAppLocalizations(const Locale('bn'));
    expect(find.text(l.settingsAboutVersion('১.০.০', '৭')), findsOneWidget);
    await tester.scrollUntilVisible(find.text('প্রথম আলো'), 300);
    expect(find.text('UN News'), findsOneWidget);
    await tester.scrollUntilVisible(find.text(l.secureScreenNotice), 300);
    expect(find.text(l.secureScreenNotice), findsOneWidget);
  });
}
