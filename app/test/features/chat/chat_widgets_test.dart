import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/features/chat/application/chat_logic.dart';
import 'package:prostuti/features/chat/data/chat_models.dart';
import 'package:prostuti/features/chat/presentation/widgets/chat_errors.dart';
import 'package:prostuti/features/chat/presentation/widgets/conversation_tile.dart';
import 'package:prostuti/features/chat/presentation/widgets/message_bubble.dart';
import 'package:prostuti/features/profile/data/profile.dart';

Widget _app(Widget child, {Locale locale = const Locale('bn')}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('bn');
    await initializeDateFormatting('en');
  });

  ConversationSummary summary({String? sender, int unread = 0, bool muted = false, String? preview}) =>
      ConversationSummary(
        id: 'c1',
        kind: ConversationKind.direct,
        otherUser: const UserSummary(id: 'u2', username: 'qa_karim', fullName: 'করিম'),
        lastMessageAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
        lastMessagePreview: preview ?? 'কেমন আছেন?',
        lastMessageSender: sender,
        unreadCount: unread,
        muted: muted,
      );

  testWidgets('inbox tile: "আপনি:" prefix for my message, Bangla time', (tester) async {
    await tester.pumpWidget(
      _app(
        ConversationTile(
          conversation: summary(sender: 'me'),
          myId: 'me',
          onTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('করিম'), findsOneWidget);
    expect(find.text('আপনি: কেমন আছেন?'), findsOneWidget);
    expect(find.text('৫ মি.'), findsOneWidget);
    expect(find.byType(UnreadBadge), findsNothing);
  });

  testWidgets('inbox tile: unread badge in Bangla digits, muted icon, localized photo preview', (tester) async {
    await tester.pumpWidget(
      _app(
        ConversationTile(
          conversation: summary(sender: 'u2', unread: 12, muted: true, preview: '📷 ছবি'),
          myId: 'me',
          onTap: () {},
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('12'), findsOneWidget);
    expect(find.text('📷 Photo'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);

    await tester.pumpWidget(
      _app(
        ConversationTile(
          conversation: summary(sender: 'u2', unread: 12),
          myId: 'me',
          onTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('১২'), findsOneWidget);
  });

  testWidgets('chat errors map backend codes to Bangla messages', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox();
          },
        ),
      ),
    );
    final l = ctx.l10n;
    expect(chatFailureMessage(ctx, const PermissionFailure('messaging_friends_only')), l.chatErrorFriendsOnly);
    expect(chatFailureMessage(ctx, const PermissionFailure('user_unavailable')), l.chatErrorUserUnavailable);
    expect(chatFailureMessage(ctx, const RateLimitFailure(retryAfterSeconds: 30)), l.chatErrorRateLimited);
    expect(chatFailureMessage(ctx, const ServerFailure('too_many_members')), l.chatErrorTooManyMembers('৪৯'));
    expect(chatFailureMessage(ctx, const NetworkFailure()), l.errorNetwork);
    // Registered globally too, so core failureMessage resolves server codes.
    registerChatFailureMessages();
    expect(failureMessage(ctx, const ServerFailure('cannot_message_self')), l.chatErrorSelf);
  });

  testWidgets('bubbles: deleted text, failed state with retry, seen receipt', (tester) async {
    var retried = 0;
    final now = DateTime.now().toUtc();
    final deleted = ChatMessage(
      id: 'd',
      conversationId: 'c',
      senderId: 'me',
      createdAt: now,
      body: 'x',
      deletedAt: now,
    );
    final failed = ChatMessage(
      id: 'f',
      conversationId: 'c',
      senderId: 'me',
      createdAt: now,
      body: 'হ্যালো',
      status: MessageStatus.failed,
    );
    final sent = ChatMessage(id: 's', conversationId: 'c', senderId: 'me', createdAt: now, body: 'ঠিক আছে');

    MessageBubble bubble(ChatMessage m, {SeenInfo? seen}) => MessageBubble(
      entry: MessageEntry(message: m, isFirstInGroup: true, isLastInGroup: true),
      isMine: true,
      isGroup: false,
      seen: seen,
      onLongPress: () {},
      onReply: () {},
      onRetry: () => retried++,
    );

    await tester.pumpWidget(
      _app(
        ListView(
          children: [
            bubble(deleted),
            bubble(failed),
            bubble(sent, seen: const SeenInfo(messageId: 's', seenBy: 1, others: 1)),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('বার্তাটি মুছে ফেলা হয়েছে'), findsOneWidget);
    expect(find.textContaining('দেখেছেন'), findsOneWidget);
    await tester.tap(find.text('পাঠানো যায়নি · আবার চেষ্টা করতে ট্যাপ করুন'));
    expect(retried, 1);
  });
}
