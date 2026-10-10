import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/features/notifications/application/notifications_controller.dart';
import 'package:prostuti/features/notifications/data/app_notification.dart';
import 'package:prostuti/features/notifications/presentation/widgets/notification_tile.dart';

void main() {
  group('notificationRoute', () {
    test('maps every type to its screen', () {
      expect(notificationRoute('friend_request', const {'request_id': 2, 'user_id': 'u1'}), Routes.friends);
      expect(notificationRoute('friend_accept', const {'user_id': 'u1'}), Routes.userProfile('u1'));
      expect(notificationRoute('post_reaction', const {'post_id': 'p1'}), Routes.postDetail('p1'));
      expect(notificationRoute('post_comment', const {'post_id': 'p1', 'comment_id': 'c'}), Routes.postDetail('p1'));
      expect(notificationRoute('comment_reply', const {'post_id': 'p2'}), Routes.postDetail('p2'));
      expect(notificationRoute('daily_notes', const {}), Routes.notes);
      expect(notificationRoute('daily_exam', const {}), Routes.dailyExam);
      expect(notificationRoute('routine', const {}), Routes.plan);
      expect(notificationRoute('plan_update', const {'schedule_id': 3}), Routes.plan);
      expect(notificationRoute('addon', const {}), Routes.addons);
      expect(notificationRoute('announcement', const {'route': '/exams'}), '/exams');
      expect(notificationRoute('announcement', const {'route': 'https://evil.example'}), isNull);
      expect(notificationRoute('announcement', const {'route': '//evil.example'}), isNull);
      expect(notificationRoute('announcement', const {}), isNull);
      expect(notificationRoute('system', const {}), isNull);
      expect(notificationRoute('something_new', const {}), isNull);
    });

    test('handles missing / malformed data', () {
      expect(notificationRoute('post_comment', const {}), isNull);
      expect(notificationRoute('post_reaction', const {'post_id': ''}), isNull);
      expect(notificationRoute('friend_accept', const {}), Routes.friends);
      // The morning routine opens its day when the id is present.
      expect(notificationRoute('routine', const {'day_id': 42, 'route': '/plan/day/42'}), Routes.planDay(42));
      expect(notificationRoute('routine', const {'day_id': 'x'}), Routes.plan);
    });
  });

  group('AppNotification', () {
    const row = {
      'id': 3,
      'type': 'post_reaction',
      'title': 'নতুন প্রতিক্রিয়া',
      'body': 'QA Karim আপনার পোস্টে প্রতিক্রিয়া জানিয়েছেন',
      'title_en': 'New reaction',
      'body_en': null,
      'data': {'post_id': 'd16d7e29-a80b-4534-95a5-7ba208ceb3ba'},
      'actor_id': 'ebe3cd4a-4457-43d9-99a5-b6fddf3fbf26',
      'read_at': null,
      'created_at': '2026-10-03T21:11:59.446034+00:00',
    };

    test('parses a live row', () {
      final n = AppNotification.fromJson(Map<String, dynamic>.from(row));
      expect(n.id, 3);
      expect(n.isRead, isFalse);
      expect(n.data['post_id'], 'd16d7e29-a80b-4534-95a5-7ba208ceb3ba');
      expect(n.cursor, NotificationCursor(DateTime.utc(2026, 10, 3, 21, 11, 59, 446, 34), 3));
      expect(AppNotification.fromJson(n.toJson()).toJson(), n.toJson());
    });

    test('bilingual text: English when available, Bangla fallback', () {
      final n = AppNotification.fromJson(Map<String, dynamic>.from(row));
      expect(n.titleFor(bangla: true), 'নতুন প্রতিক্রিয়া');
      expect(n.titleFor(bangla: false), 'New reaction');
      expect(n.bodyFor(bangla: false), startsWith('QA Karim')); // body_en null → Bangla
    });

    test('data delivered as a JSON string (Realtime) is decoded', () {
      final n = AppNotification.fromJson(Map<String, dynamic>.from(row)..['data'] = '{"post_id":"p9"}');
      expect(n.data['post_id'], 'p9');
      expect(AppNotification.fromJson(Map<String, dynamic>.from(row)..['data'] = 'not json').data, isEmpty);
    });
  });

  group('applyPendingActions', () {
    final now = DateTime.utc(2026, 10, 4);
    AppNotification n(int id, {bool read = false}) =>
        AppNotification(id: id, type: 'system', title: 't$id', createdAt: now, readAt: read ? now : null);

    test('queued read/delete actions are reflected on fresh data', () {
      final items = [n(1), n(2), n(3, read: true)];
      final out = applyPendingActions(items, readIds: {1}, deletedIds: {3}, allRead: false, now: now);
      expect([for (final x in out) (x.id, x.isRead)], [(1, true), (2, false)]);
    });

    test('a queued "mark all read" marks everything', () {
      final out = applyPendingActions([n(1), n(2)], readIds: const {}, deletedIds: const {}, allRead: true, now: now);
      expect(out.every((x) => x.isRead), isTrue);
    });

    test('nothing pending → same list instance', () {
      final items = [n(1)];
      expect(applyPendingActions(items, readIds: const {}, deletedIds: const {}, allRead: false), same(items));
    });
  });

  testWidgets('tile shows English text in English UI and highlights unread', (tester) async {
    Widget app(Locale locale, AppNotification n) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: NotificationTile(notification: n, onTap: () {}),
      ),
    );
    final n = AppNotification(
      id: 1,
      type: 'friend_request',
      title: 'নতুন বন্ধুত্বের অনুরোধ',
      titleEn: 'New friend request',
      body: 'রহিম আপনাকে অনুরোধ পাঠিয়েছেন',
      createdAt: DateTime.now().toUtc(),
    );
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(app(const Locale('en'), n));
    expect(find.text('New friend request'), findsOneWidget);
    expect(find.text('রহিম আপনাকে অনুরোধ পাঠিয়েছেন'), findsOneWidget); // no body_en → Bangla
    expect(find.bySemanticsLabel(RegExp('Unread')), findsOneWidget);
    expect(find.byIcon(Icons.person_add_alt_1_rounded), findsOneWidget);

    await tester.pumpWidget(app(const Locale('bn'), n.copyWith(readAt: DateTime.now())));
    expect(find.text('নতুন বন্ধুত্বের অনুরোধ'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('অপঠিত')), findsNothing);
    semantics.dispose();
  });
}
