import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/core/cache/cache_store.dart';
import 'package:prostuti/core/cache/cached_fetcher.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/pagination/paged_state.dart';
import 'package:prostuti/core/theme/app_theme.dart';
import 'package:prostuti/features/feed/application/feed_controller.dart';
import 'package:prostuti/features/feed/application/reaction_controller.dart';
import 'package:prostuti/features/feed/data/post.dart';
import 'package:prostuti/features/friends/application/relationship_controller.dart';
import 'package:prostuti/features/friends/data/friends_repository.dart';
import 'package:prostuti/features/friends/data/relationship.dart';
import 'package:prostuti/features/friends/presentation/screens/user_profile_screen.dart';
import 'package:prostuti/features/profile/data/profile.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeRepo extends FriendsRepository {
  _FakeRepo(CachedFetcher cache, this.answer)
    : super(
        SupabaseClient('http://localhost', 'anon', authOptions: const AuthClientOptions(autoRefreshToken: false)),
        cache,
      );
  final Relationship answer;

  @override
  Future<Relationship> relationship(String userId) async => answer;

  @override
  Future<void> rememberRelationship(String userId, Relationship r) async {}
}

class _FakeAuthorFeed extends AuthorFeedNotifier {
  _FakeAuthorFeed(super.authorId);

  @override
  PagedState<Post, Keyset> build() => PagedState(
    items: [
      Post(
        id: 'p1',
        author: UserSummary(id: authorId, username: 'karim'),
        body: 'আমার প্রথম পোস্ট',
        createdAt: DateTime.now().subtract(const Duration(minutes: 3)),
      ),
    ],
    isLoadingFirst: false,
    hasMore: false,
  );
}

const _karim = Profile(
  id: 'k1',
  username: 'qa_karim',
  fullName: 'করিম হোসেন',
  bio: '৪৭তম বিসিএস প্রার্থী',
  district: 'রাজশাহী',
  friendsCount: 12,
  postsCount: 4,
  examsTaken: 31,
  streakCount: 9,
);

Future<void> _pump(WidgetTester tester, {required String me, required Relationship rel}) async {
  final cache = CachedFetcher((await tester.runAsync(CacheStore.inMemory))!);
  final reactions = ReactionController(send: (_, _) async => null, publish: (_) {});
  addTearDown(reactions.dispose);
  tester.view
    ..physicalSize = const Size(480, 1600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      // No automatic retries in tests (they leave timers pending).
      retry: (_, _) => null,
      overrides: [
        currentUserIdProvider.overrideWithValue(me),
        friendsRepositoryProvider.overrideWithValue(_FakeRepo(cache, rel)),
        profileByIdProvider.overrideWith((ref, id) async => _karim),
        authorFeedProvider.overrideWith2(_FakeAuthorFeed.new),
        reactionControllerProvider.overrideWithValue(reactions),
      ],
      child: MaterialApp(
        locale: const Locale('bn'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: const UserProfileScreen(userId: 'k1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('another user: header, stats, add-friend + message, posts', (tester) async {
    await _pump(tester, me: 'me', rel: Relationship.none);
    expect(find.text('করিম হোসেন'), findsWidgets);
    expect(find.text('@qa_karim'), findsOneWidget);
    expect(find.text('৪৭তম বিসিএস প্রার্থী'), findsOneWidget);
    expect(find.text('রাজশাহী'), findsOneWidget);
    expect(find.text('১২'), findsOneWidget);
    expect(find.text('৩১'), findsOneWidget);
    expect(find.text('৯'), findsOneWidget);
    expect(find.text('বন্ধু যোগ করুন'), findsOneWidget);
    expect(find.text('মেসেজ'), findsOneWidget);
    expect(find.text('আমার প্রথম পোস্ট'), findsOneWidget);
    expect(find.text('প্রোফাইল সম্পাদনা'), findsNothing);
  });

  testWidgets('incoming request shows confirm / delete', (tester) async {
    await _pump(tester, me: 'me', rel: const Relationship(RelationshipStatus.requestReceived, requestId: 5));
    expect(find.text('নিশ্চিত করুন'), findsOneWidget);
    expect(find.text('মুছুন'), findsOneWidget);
  });

  testWidgets('blocked user shows unblock and the notice, no message button', (tester) async {
    await _pump(tester, me: 'me', rel: Relationship.blocked);
    expect(find.text('আনব্লক করুন'), findsOneWidget);
    expect(find.text('মেসেজ'), findsNothing);
    expect(find.textContaining('আপনি এই ব্যবহারকারীকে ব্লক করেছেন'), findsOneWidget);
  });

  testWidgets('my own profile offers edit instead of relationship buttons', (tester) async {
    await _pump(tester, me: 'k1', rel: Relationship.self);
    expect(find.text('প্রোফাইল সম্পাদনা'), findsOneWidget);
    expect(find.text('বন্ধু যোগ করুন'), findsNothing);
    expect(find.text('মেসেজ'), findsNothing);
  });

  test('seeds are used before the network', () {
    final seeds = RelationshipSeeds()..put('x', Relationship.friends);
    expect(seeds['x'], Relationship.friends);
  });
}
