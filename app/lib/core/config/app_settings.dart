import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/network/supabase_providers.dart';

/// Device-local UI preferences (theme + language), persisted in the cache box.
@immutable
class AppSettings {
  const AppSettings({this.themeMode = ThemeMode.system, this.locale = const Locale('bn'), this.localeChosen = false});

  final ThemeMode themeMode;
  final Locale locale;

  /// True once the user picked a language on this device; until then the
  /// language saved in their profile (if any) is adopted after sign-in.
  final bool localeChosen;

  AppSettings copyWith({ThemeMode? themeMode, Locale? locale, bool? localeChosen}) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    locale: locale ?? this.locale,
    localeChosen: localeChosen ?? this.localeChosen,
  );
}

class AppSettingsNotifier extends Notifier<AppSettings> {
  static const _key = 'app_settings';

  @override
  AppSettings build() {
    final raw = ref.read(cacheStoreProvider).read(_key)?.data;
    if (raw is! Map) return const AppSettings();
    return AppSettings(
      themeMode: ThemeMode.values.firstWhere((m) => m.name == raw['theme'], orElse: () => ThemeMode.system),
      locale: Locale(raw['locale'] == 'en' ? 'en' : 'bn'),
      localeChosen: raw['chosen'] == true,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) => _save(state.copyWith(themeMode: mode));

  Future<void> setLocale(Locale locale) => _save(state.copyWith(locale: locale, localeChosen: true));

  /// Applies the profile's language on a fresh install (never overrides an
  /// explicit choice made on this device).
  Future<void> adoptProfileLocale(String code) async {
    if (state.localeChosen || code == state.locale.languageCode) return;
    await _save(state.copyWith(locale: Locale(code == 'en' ? 'en' : 'bn')));
  }

  Future<void> _save(AppSettings next) {
    state = next;
    return ref.read(cacheStoreProvider).write(_key, {
      'theme': next.themeMode.name,
      'locale': next.locale.languageCode,
      'chosen': next.localeChosen,
    }, const Duration(days: 3650));
  }
}

final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(AppSettingsNotifier.new);
