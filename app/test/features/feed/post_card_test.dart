import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/core/cache/cache_store.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/theme/app_theme.dart';
import 'package:prostuti/features/bookmarks/data/bookmark.dart';
import 'package:prostuti/features/bookmarks/data/bookmarks_repository.dart';
import 'package:prostuti/features/feed/application/reaction_controller.dart';
import 'package:prostuti/features/feed/data/post.dart';
import 'package:prostuti/features/feed/presentation/widgets/post_card.dart';
import 'package:prostuti/features/profile/data/profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeBookmarks extends BookmarksRepository {
  _FakeBookmarks(CacheStore store)
    : super(
        SupabaseClient('http://localhost', 'anon', authOptions: const AuthClientOptions(autoRefreshToken: false)),
        store,
      );

  final saved = <Bookmark>[];

  @override
  Future<bool> restore(Bookmark b) async {
    saved.add(b);
    return true;
  }
}

Post _post({
  String body = 'আজ ৫০টি প্রশ্ন অনুশীলন করলাম',
  PostKind kind = PostKind.text,
  Map<String, dynamic> meta = const {},
}) => Post(
  id: 'p1',
  author: const UserSummary(id: 'u1', username: 'rahim', fullName: 'রহিম উদ্দিন'),
  body: body,
  kind: kind,
  meta: meta,
  createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
  reactionCount: 4,
  commentCount: 2,
  reactionSummary: const {ReactionType.like: 3, ReactionType.love: 1},
);

void main() {
  late List<(String, ReactionType?)> sent;
  late List<Post> published;
  late CacheStore store;
  late _FakeBookmarks bookmarks;

  setUpAll(() async => store = await CacheStore.inMemory());

  Future<void> pump(WidgetTester tester, Post post) async {
    sent = [];
    published = [];
    bookmarks = _FakeBookmarks(store);
    final controller = ReactionController(
      send: (id, type) async {
        sent.add((id, type));
        return null; // behave like a queued write
      },
      publish: published.add,
      interval: Duration.zero,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('me'),
          reactionControllerProvider.overrideWithValue(controller),
          bookmarksRepositoryProvider.overrideWithValue(bookmarks),
        ],
        child: MaterialApp(
          locale: const Locale('bn'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(child: PostCard(post: post)),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows author, relative time, body, counts in Bangla digits', (tester) async {
    await pump(tester, _post());
    expect(find.text('রহিম উদ্দিন'), findsOneWidget);
    expect(find.textContaining('৫ মিনিট আগে'), findsOneWidget);
    expect(find.text('আজ ৫০টি প্রশ্ন অনুশীলন করলাম'), findsOneWidget);
    expect(find.text('৪'), findsOneWidget);
    expect(find.text('২টি মন্তব্য'), findsOneWidget);
    expect(find.text('লাইক'), findsOneWidget);
    expect(find.text('আরও দেখুন'), findsNothing);
  });

  testWidgets('long posts collapse with a See more toggle', (tester) async {
    await pump(tester, _post(body: List.filled(40, 'বিসিএস প্রস্তুতির জন্য প্রতিদিন পড়ুন।').join('\n')));
    expect(find.text('আরও দেখুন'), findsOneWidget);
    await tester.tap(find.text('আরও দেখুন'));
    await tester.pumpAndSettle();
    expect(find.text('কম দেখুন'), findsOneWidget);
  });

  testWidgets('tapping React likes optimistically', (tester) async {
    await pump(tester, _post());
    await tester.tap(find.text('লাইক'));
    await tester.pump();
    expect(sent.single, ('p1', ReactionType.like));
    expect(published.single.myReaction, ReactionType.like);
    expect(published.single.reactionCount, 5);
  });

  testWidgets('Save post bookmarks a Post.toJson snapshot', (tester) async {
    final l = lookupAppLocalizations(const Locale('bn'));
    await pump(tester, _post());
    await tester.tap(find.byTooltip(l.feedPostOptions));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.feedSavePost));
    await tester.pumpAndSettle();
    final b = bookmarks.saved.single;
    expect(b.key, 'post:p1');
    final saved = BookmarkedPost.fromPayload(b.payload);
    expect(saved.displayName, 'রহিম উদ্দিন');
    expect(saved.body, 'আজ ৫০টি প্রশ্ন অনুশীলন করলাম');
    expect(find.text(l.feedPostSaved), findsOneWidget);
  });

  testWidgets('exam_result posts render a score card', (tester) async {
    await pump(
      tester,
      _post(
        body: '',
        kind: PostKind.examResult,
        meta: const {'title': 'মডেল টেস্ট ৩', 'score': 45.5, 'max_score': 100, 'correct': 50, 'wrong': 9, 'total': 100},
      ),
    );
    expect(find.text('পরীক্ষার ফলাফল'), findsOneWidget);
    expect(find.text('মডেল টেস্ট ৩'), findsOneWidget);
    expect(find.textContaining('৪৫.৫'), findsOneWidget);
    expect(find.text('সঠিক ৫০'), findsOneWidget);
    expect(find.text('ভুল ৯'), findsOneWidget);
  });
}
