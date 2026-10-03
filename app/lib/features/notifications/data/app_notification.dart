import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/utils/json.dart';

/// Keyset cursor `(created_at, id)` — ties on `created_at` are broken by id,
/// so paging never skips or repeats a notification.
@immutable
class NotificationCursor {
  const NotificationCursor(this.createdAt, this.id);
  final DateTime createdAt;
  final int id;

  @override
  bool operator ==(Object other) => other is NotificationCursor && other.createdAt == createdAt && other.id == id;

  @override
  int get hashCode => Object.hash(createdAt, id);
}

/// One row of the in-app inbox (`public.notifications`).
@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.createdAt,
    this.body,
    this.titleEn,
    this.bodyEn,
    this.data = const {},
    this.actorId,
    this.readAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
    id: j.integer('id'),
    type: j.str('type', 'system'),
    title: j.str('title'),
    body: j.strOrNull('body'),
    titleEn: j.strOrNull('title_en'),
    bodyEn: j.strOrNull('body_en'),
    data: _data(j['data']),
    actorId: j.strOrNull('actor_id'),
    readAt: j.date('read_at'),
    createdAt: j.dateOr('created_at', DateTime.now().toUtc()),
  );

  /// Explicit column list (Bangla + English text).
  static const columns = 'id, type, title, body, title_en, body_en, data, actor_id, read_at, created_at';

  final int id;
  final String type;
  final String title;
  final String? body;
  final String? titleEn;
  final String? bodyEn;
  final Map<String, dynamic> data;
  final String? actorId;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isRead => readAt != null;

  NotificationCursor get cursor => NotificationCursor(createdAt, id);

  /// English text when the UI is English and it exists; Bangla otherwise.
  String titleFor({required bool bangla}) => !bangla && (titleEn?.trim().isNotEmpty ?? false) ? titleEn! : title;

  String? bodyFor({required bool bangla}) => !bangla && (bodyEn?.trim().isNotEmpty ?? false) ? bodyEn : body;

  AppNotification copyWith({DateTime? readAt, bool clearReadAt = false}) => AppNotification(
    id: id,
    type: type,
    title: title,
    body: body,
    titleEn: titleEn,
    bodyEn: bodyEn,
    data: data,
    actorId: actorId,
    readAt: clearReadAt ? null : (readAt ?? this.readAt),
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'title': title,
    'body': body,
    'title_en': titleEn,
    'body_en': bodyEn,
    'data': data,
    'actor_id': actorId,
    'read_at': readAt?.toUtc().toIso8601String(),
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  static Map<String, dynamic> _data(Object? raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } on FormatException {
        return const {};
      }
    }
    return const {};
  }
}

/// Where tapping a notification leads (null = nowhere, e.g. `system`).
String? notificationRoute(String type, Map<String, dynamic> data) {
  String? read(String key) {
    final v = data[key]?.toString().trim();
    return v == null || v.isEmpty ? null : v;
  }

  return switch (type) {
    'friend_request' => Routes.friends,
    'friend_accept' => switch (read('user_id')) {
      final userId? => Routes.userProfile(userId),
      null => Routes.friends,
    },
    'post_reaction' || 'post_comment' || 'comment_reply' => switch (read('post_id')) {
      final postId? => Routes.postDetail(postId),
      null => null,
    },
    'daily_notes' => Routes.notes,
    'daily_exam' => Routes.dailyExam,
    // The morning routine carries its day: open it directly when present.
    'routine' => switch (int.tryParse(read('day_id') ?? '')) {
      final dayId? => Routes.planDay(dayId),
      null => Routes.plan,
    },
    'plan_update' => Routes.plan,
    'addon' => Routes.addons,
    _ => null,
  };
}
