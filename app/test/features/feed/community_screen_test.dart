import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/pagination/paged_state.dart';
import 'package:prostuti/core/theme/app_theme.dart';
import 'package:prostuti/features/feed/application/feed_controller.dart';
import 'package:prostuti/features/feed/application/reaction_controller.dart';
import 'package:prostuti/features/feed/data/post.dart';
import 'package:prostuti/features/feed/presentation/screens/community_screen.dart';
import 'package:prostuti/features/friends/application/friends_controller.dart';
import 'package:prostuti/features/profile/data/profile.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';

class _FakeFeed extends FeedNotifier {
  _FakeFeed(this.posts);
  final List<Post> posts;

  @override
  PagedState<Post, Keyset> build() => PagedState(items: posts, isLoadingFirst: false, hasMore: false);
}

class _FakeProfile extends CurrentProfileNotifier {
  @override
  Future<Profile?> build() async => const Profile(id: 'me', username: 'me_user', fullName: 'আমি');
}

Post _post(String id, String body) => Post(
  id: id,
  author: const UserSummary(id: 'u1', username: 'nadia', fullName: 'নাদিয়া'),
  body: body,
  createdAt: DateTime.now().subtract(const Duration(hours: 2)),
);

Future<void> _pump(WidgetTester tester, List<Post> posts) async {
  final reactions = ReactionController(send: (_, _) async => null, publish: (_) {});
  addTearDown(reactions.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        feedProvider.overrideWith(() => _FakeFeed(posts)),
        currentProfileProvider.overrideWith(_FakeProfile.new),
        currentUserIdProvider.overrideWithValue('me'),
        reactionControllerProvider.overrideWithValue(reactions),
        incomingRequestCountProvider.overrideWith((ref) async => 3),
        unreadChatsCountProvider.overrideWith((ref) async => 120),
      ],
      child: MaterialApp(
        locale: const Locale('bn'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.dark(),
        home: const CommunityScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('feed shows the composer prompt, posts and app-bar badges', (tester) async {
    await _pump(tester, [_post('a', 'প্রথম পোস্ট'), _post('b', 'দ্বিতীয় পোস্ট')]);
    expect(find.text('কমিউনিটি'), findsOneWidget);
    expect(find.text('কী ভাবছেন?'), findsOneWidget);
    expect(find.text('প্রথম পোস্ট'), findsOneWidget);
    expect(find.text('দ্বিতীয় পোস্ট'), findsOneWidget);
    expect(find.text('৩'), findsOneWidget, reason: 'pending friend requests badge');
    expect(find.text('৯৯+'), findsOneWidget, reason: 'unread chats badge is capped');
    expect(find.byTooltip('মানুষ খুঁজুন'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty feed invites the first post', (tester) async {
    await _pump(tester, const []);
    expect(find.text('এখনো কোনো পোস্ট নেই'), findsOneWidget);
    expect(find.text('পোস্ট লিখুন'), findsOneWidget);
  });
}
