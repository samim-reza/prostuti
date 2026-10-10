import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prostuti/app.dart';
import 'package:prostuti/core/cache/cache_store.dart';
import 'package:prostuti/core/config/app_constants.dart';
import 'package:prostuti/core/config/env.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/offline/offline_queue.dart';
import 'package:prostuti/core/router/app_router.dart';
import 'package:prostuti/core/services/ads_service.dart';
import 'package:prostuti/core/services/error_reporter.dart';
import 'package:prostuti/core/services/notification_service.dart';
import 'package:prostuti/core/services/push_service.dart';
import 'package:prostuti/core/services/screen_security.dart';
import 'package:prostuti/core/theme/app_theme.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// App start-up. Only work needed for the first frame is awaited; everything
/// else (ads SDK, push, notification channels) warms up in the background so
/// cold start stays fast on low-end phones.
Future<void> bootstrap() async {
  await runZonedGuarded(
    () async {
      final binding = WidgetsFlutterBinding.ensureInitialized()..deferFirstFrame();
      _installErrorHandlers();
      await _start(binding);
    },
    (error, stack) {
      if (kDebugMode) debugPrint('Uncaught: $error\n$stack');
      ErrorReporter.instance.record(error, stack, fatal: true);
    },
  );
}

/// Errors are printed in debug builds and reported (release only, see
/// [ErrorReporter]) from all three entry points: framework errors, errors
/// outside any zone (platform callbacks) and the guarded zone above.
void _installErrorHandlers() {
  final reporter = ErrorReporter.instance
    ..routeResolver = _currentRoute
    ..localeResolver = _currentLocale;
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    reporter.recordFlutterError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    if (kDebugMode) debugPrint('Uncaught (platform): $error\n$stack');
    reporter.record(error, stack, fatal: true);
    return true;
  };
}

/// Route pattern of the top GoRouter page (`/exam/:id`, no ids or query).
String? _currentRoute() {
  final context = rootNavigatorKey.currentContext;
  if (context == null) return null;
  final state = GoRouter.maybeOf(context)?.state;
  return state?.fullPath ?? state?.uri.path;
}

String? _currentLocale() {
  final context = rootNavigatorKey.currentContext;
  return context == null ? null : Localizations.maybeLocaleOf(context)?.languageCode;
}

bool _firstFrameAllowed = false;

void _allowFirstFrame(WidgetsBinding binding) {
  if (_firstFrameAllowed) return;
  _firstFrameAllowed = true;
  binding.allowFirstFrame();
}

/// Every step is idempotent, so the failure screen can simply run it again.
Future<void> _start(WidgetsBinding binding) async {
  try {
    if (kReleaseMode && !Env.isConfigured) {
      throw StateError('SUPABASE_ANON_KEY was not provided at build time');
    }

    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    await Future.wait([Hive.initFlutter('prostuti'), initializeDateFormatting('bn'), initializeDateFormatting('en')]);

    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey.isEmpty ? 'missing-anon-key' : Env.supabaseAnonKey,
      realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 10),
    );
    final client = Supabase.instance.client;
    ErrorReporter.instance.attach((params) async {
      await client.rpc<dynamic>('log_client_error', params: params);
    });

    final cache = await CacheStore.open();
    await Future.wait([ConnectivityService.instance.init(), OfflineQueue.instance.init()]);

    // Non-blocking warm-ups.
    unawaited(NotificationService.instance.init());
    unawaited(ScreenSecurity.instance.init());
    unawaited(AdsService.instance.init());
    unawaited(PushService.instance.init());

    runApp(
      ProviderScope(
        overrides: [cacheStoreProvider.overrideWithValue(cache)],
        // Riverpod retries failed providers automatically; only transient
        // network failures are worth retrying (not 402/403/404/429).
        retry: (count, error) {
          if (count >= 2) return null;
          final failure = AppFailure.from(error);
          return failure is NetworkFailure ? Duration(milliseconds: 600 * (count + 1)) : null;
        },
        child: const ProstutiApp(),
      ),
    );
  } on Object catch (error, stack) {
    // Without this the native splash would stay up forever.
    if (kDebugMode) debugPrint('Start-up failed: $error\n$stack');
    ErrorReporter.instance.record(error, stack, fatal: true, context: 'startup');
    runApp(_StartupFailedApp(onRetry: () => _start(binding)));
  } finally {
    _allowFirstFrame(binding);
  }
}

/// Minimal, dependency-free screen shown when start-up fails (e.g. local
/// storage can't be opened). Uses the phone's language.
class _StartupFailedApp extends StatefulWidget {
  const _StartupFailedApp({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  State<_StartupFailedApp> createState() => _StartupFailedAppState();
}

class _StartupFailedAppState extends State<_StartupFailedApp> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    await widget.onRetry();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: SafeArea(
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : EmptyView(
                    icon: Icons.error_outline_rounded,
                    title: context.l10n.authStartupFailedTitle,
                    message: context.l10n.authStartupFailedBody(AppConstants.supportEmail),
                    action: () => unawaited(_retry()),
                    actionLabel: context.l10n.retry,
                  ),
          ),
        ),
      ),
    );
  }
}
