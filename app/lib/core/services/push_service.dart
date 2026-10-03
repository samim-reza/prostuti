import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:prostuti/core/config/env.dart';
import 'package:prostuti/core/services/notification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Optional Firebase Cloud Messaging. Activated only when Firebase options
/// are supplied at build time (`FIREBASE_*` dart-defines); otherwise every
/// method is a no-op and the app relies on local notifications + the
/// in-app (Realtime) notification inbox.
class PushService {
  PushService._();
  static final instance = PushService._();

  bool _enabled = false;
  bool get enabled => _enabled;

  Future<void> init() async {
    if (kIsWeb || !Env.firebaseEnabled) return;
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: Env.firebaseApiKey,
          appId: Env.firebaseAppId,
          messagingSenderId: Env.firebaseSenderId,
          projectId: Env.firebaseProjectId,
        ),
      );
      _enabled = true;
      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n == null) return;
        unawaited(
          NotificationService.instance.show(
            title: n.title ?? '',
            body: n.body ?? '',
            payload: m.data['route']?.toString(),
          ),
        );
      });
    } on Object catch (e) {
      debugPrint('Push disabled: $e');
    }
  }

  /// Registers this device's token for the signed-in user.
  Future<void> registerDevice(SupabaseClient client) async {
    if (!_enabled || client.auth.currentUser == null) return;
    try {
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await client.rpc<void>(
        'register_device_token',
        params: {'p_token': token, 'p_platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android'},
      );
      FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        unawaited(client.rpc<void>('register_device_token', params: {'p_token': t}));
      });
    } on Object catch (e) {
      debugPrint('Push token registration failed: $e');
    }
  }
}
