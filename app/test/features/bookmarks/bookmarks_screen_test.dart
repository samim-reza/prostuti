import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prostuti/core/cache/cache_store.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/pagination/paged_state.dart';
import 'package:prostuti/core/theme/app_theme.dart';
import 'package:prostuti/features/bookmarks/data/bookmark.dart';
import 'package:prostuti/features/bookmarks/data/bookmarks_repository.dart';
import 'package:prostuti/features/bookmarks/presentation/screens/bookmarks_screen.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeRepo extends BookmarksRepository {
  _FakeRepo(CacheStore store)
    : super(
        SupabaseClient('http://localhost', 'anon', authOptions: const AuthClientOptions(autoRefreshToken: false)),
        store,
      );

  final items = [
    Bookmark(
      type: BookmarkType.question,
      itemId: '1',
      createdAt: DateTime.now().toUtc(),
      payload: const {
        'stem': 'প্রথম প্রশ্ন?',
        'options': ['ক', 'খ'],
        'correct_index': 1,
      },
    ),
    Bookmark(
      type: BookmarkType.question,
      itemId: '2',
      createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      payload: const {
        'stem': 'দ্বিতীয় প্রশ্ন?',
        'options': ['গ', 'ঘ'],
      },
    ),
  ];
  final removed = <String>[];
  final restored = <String>[];

  @override
  String? get uid => 'u1';

  @override
  Future<PageResult<Bookmark, BookmarkCursor>> page(BookmarkType type, BookmarkCursor? after) async =>
      PageResult(items.where((b) => b.type == type).toList(), null);

  @override
  Future<bool> remove(Bookmark b) async {
    removed.add(b.key);
    return true;
  }

  @override
  Future<bool> restore(Bookmark b) async {
    restored.add(b.key);
    return true;
  }
}

void main() {
  late CacheStore store;

  setUpAll(() async {
    await initializeDateFormatting('bn');
    store = await CacheStore.inMemory();
  });

  testWidgets('swipe removes a bookmark and undo brings it back in place', (tester) async {
    final repo = _FakeRepo(store);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookmarksRepositoryProvider.overrideWithValue(repo),
          subjectsProvider.overrideWith((ref) async => const <Subject>[]),
        ],
        child: MaterialApp(
          locale: const Locale('bn'),
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const BookmarksScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l = lookupAppLocalizations(const Locale('bn'));
    expect(find.text('প্রথম প্রশ্ন?'), findsOneWidget);
    expect(find.text('দ্বিতীয় প্রশ্ন?'), findsOneWidget);
    // Unknown answer → hint instead of a highlighted option.
    expect(find.text(l.bookmarksAnswerUnknown), findsOneWidget);

    await tester.drag(find.text('প্রথম প্রশ্ন?'), const Offset(-700, 0));
    await tester.pumpAndSettle();
    expect(find.text('প্রথম প্রশ্ন?'), findsNothing);
    expect(repo.removed, ['question:1']);
    expect(find.text(l.bookmarksRemoved), findsOneWidget);

    await tester.tap(find.text(l.bookmarksUndo));
    await tester.pumpAndSettle();
    expect(repo.restored, ['question:1']);
    expect(find.text('প্রথম প্রশ্ন?'), findsOneWidget);
    // Restored above the second item (original position).
    expect(
      tester.getTopLeft(find.text('প্রথম প্রশ্ন?')).dy,
      lessThan(tester.getTopLeft(find.text('দ্বিতীয় প্রশ্ন?')).dy),
    );

    // Other tabs show their own empty states.
    await tester.tap(find.text(l.bookmarksTabNotes));
    await tester.pumpAndSettle();
    expect(find.text(l.bookmarksEmptyNotes), findsOneWidget);
  });
}
