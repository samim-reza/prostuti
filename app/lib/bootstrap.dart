import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prostuti/app.dart';
import 'package:prostuti/core/cache/cache_store.dart';
import 'package:prostuti/core/config/env.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/offline/offline_queue.dart';
import 'package:prostuti/core/services/ads_service.dart';
import 'package:prostuti/core/services/notification_service.dart';
import 'package:prostuti/core/services/push_service.dart';
import 'package:prostuti/core/services/screen_security.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// App start-up. Only work needed for the first frame is awaited; everything
/// else (ads SDK, push, notification channels) warms up in the background so
/// cold start stays fast on low-end phones.
Future<void> bootstrap() async {
  await runZonedGuarded(
    () async {
      final binding = WidgetsFlutterBinding.ensureInitialized()..deferFirstFrame();

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        if (kReleaseMode) debugPrint('FlutterError: ${details.exceptionAsString()}');
      };

      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

      await Future.wait([Hive.initFlutter('prostuti'), initializeDateFormatting('bn'), initializeDateFormatting('en')]);

      await Supabase.initialize(
        url: Env.supabaseUrl,
        publishableKey: Env.supabaseAnonKey.isEmpty ? 'missing-anon-key' : Env.supabaseAnonKey,
        realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 10),
      );

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
      binding.allowFirstFrame();
    },
    (error, stack) {
      debugPrint('Uncaught: $error\n$stack');
    },
  );
}
