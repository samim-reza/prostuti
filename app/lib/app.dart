import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/config/app_gate.dart';
import 'package:prostuti/core/config/app_settings.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/offline/offline_banner.dart';
import 'package:prostuti/core/offline/offline_queue.dart';
import 'package:prostuti/core/router/app_router.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/services/notification_service.dart';
import 'package:prostuti/core/services/push_service.dart';
import 'package:prostuti/core/services/screen_security.dart';
import 'package:prostuti/core/theme/app_theme.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';
import 'package:prostuti/offline_sync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProstutiApp extends ConsumerStatefulWidget {
  const ProstutiApp({super.key});

  @override
  ConsumerState<ProstutiApp> createState() => _ProstutiAppState();
}

class _ProstutiAppState extends ConsumerState<ProstutiApp> {
  StreamSubscription<String>? _taps;

  @override
  void initState() {
    super.initState();
    // Notification taps carry the route to open.
    _taps = NotificationService.instance.taps.listen((route) {
      if (route.startsWith('/')) unawaited(ref.read(appRouterProvider).push(route));
    });
    // Replay writes queued while offline (in this or a previous session).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      registerOfflineHandlers(ref);
      unawaited(OfflineQueue.instance.flush());
    });
  }

  @override
  void dispose() {
    unawaited(_taps?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final settings = ref.watch(appSettingsProvider);

    // Password-recovery links open the "set new password" screen; every
    // sign-in registers the device for push (no-op without Firebase).
    ref.listen(authStateProvider, (_, next) {
      final event = next.value?.event;
      if (event == AuthChangeEvent.passwordRecovery) router.go(Routes.resetPassword);
      if (event == AuthChangeEvent.signedIn) {
        unawaited(PushService.instance.registerDevice(ref.read(supabaseProvider)));
      }
    });

    // Fresh install + existing account → use the language saved in the profile.
    ref.listen(currentProfileProvider.select((p) => p.value?.locale), (_, code) {
      if (code != null) unawaited(ref.read(appSettingsProvider.notifier).adoptProfileLocale(code));
    });

    return MaterialApp.router(
      title: 'Prostuti',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      locale: settings.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        // Respect the user's font scale but cap it so exam layouts never break.
        final media = MediaQuery.of(context);
        final scaler = media.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.3);
        return MediaQuery(
          data: media.copyWith(textScaler: scaler),
          child: ScreenSecurityShield(
            child: OfflineBanner(child: AppGate(child: child ?? const SizedBox.shrink())),
          ),
        );
      },
    );
  }
}

/// Convenience for screens: `context.goHome()`.
extension NavX on BuildContext {
  void goHome() => go(Routes.home);
}
