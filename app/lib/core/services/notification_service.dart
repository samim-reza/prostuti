import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// On-device scheduled notifications. These work with no backend and no
/// Firebase: the daily exam reminder (user-chosen time) and the morning
/// routine nudge are scheduled locally, in Bangladesh time.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Taps on notifications are forwarded here (payload = route to open).
  final _taps = StreamController<String>.broadcast();
  Stream<String> get taps => _taps.stream;

  static const reminderId = 1001;
  static const morningRoutineId = 1002;

  static const _channelReminders = AndroidNotificationChannel(
    'prostuti_reminders',
    'Study reminders',
    description: 'Daily exam reminders and morning routine',
    importance: Importance.high,
  );
  static const _channelGeneral = AndroidNotificationChannel(
    'prostuti_general',
    'General',
    description: 'Friend requests, comments, new notes and messages',
  );

  Future<void> init() async {
    if (kIsWeb || _ready) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Dhaka'));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        if (r.payload != null && r.payload!.isNotEmpty) _taps.add(r.payload!);
      },
    );
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_channelReminders);
    await android?.createNotificationChannel(_channelGeneral);

    final launch = await _plugin.getNotificationAppLaunchDetails();
    final payload = launch?.notificationResponse?.payload;
    if ((launch?.didNotificationLaunchApp ?? false) && payload != null) {
      scheduleMicrotask(() => _taps.add(payload));
    }
    _ready = true;
  }

  Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    final granted =
        await android?.requestNotificationsPermission() ??
        await ios?.requestPermissions(alert: true, badge: true, sound: true) ??
        false;
    return granted;
  }

  NotificationDetails _details(AndroidNotificationChannel channel) => NotificationDetails(
    android: AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: channel.importance,
      priority: Priority.high,
      color: const Color(0xFF006A4E),
      styleInformation: const BigTextStyleInformation(''),
    ),
    iOS: const DarwinNotificationDetails(),
  );

  /// Next occurrence of [time] in Bangladesh time.
  tz.TZDateTime _nextInstance(TimeOfDay time) {
    final now = tz.TZDateTime.now(tz.local);
    var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, time.hour, time.minute);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    return at;
  }

  /// Repeats daily. Uses inexact alarms (no SCHEDULE_EXACT_ALARM permission,
  /// battery friendly; Android may shift it by a few minutes).
  Future<void> scheduleDaily({
    required int id,
    required TimeOfDay time,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (kIsWeb || !_ready) return;
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: _nextInstance(time),
      notificationDetails: _details(_channelReminders),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: payload,
    );
  }

  Future<void> cancel(int id) async {
    if (kIsWeb || !_ready) return;
    await _plugin.cancel(id: id);
  }

  Future<void> show({required String title, required String body, String? payload, int? id}) async {
    if (kIsWeb || !_ready) return;
    await _plugin.show(
      id: id ?? DateTime.now().millisecondsSinceEpoch.remainder(1 << 30),
      title: title,
      body: body,
      notificationDetails: _details(_channelGeneral),
      payload: payload,
    );
  }
}

final notificationServiceProvider = Provider<NotificationService>((ref) => NotificationService.instance);

/// Parses "HH:mm" → [TimeOfDay].
TimeOfDay parseTimeOfDay(String hhmm, {TimeOfDay fallback = const TimeOfDay(hour: 20, minute: 0)}) {
  final parts = hhmm.split(':');
  if (parts.length < 2) return fallback;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return fallback;
  return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
}
