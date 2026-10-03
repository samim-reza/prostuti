// ignore_for_file: cascade_invocations
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/core/cache/cache_store.dart';
import 'package:prostuti/core/cache/cached_fetcher.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/features/friends/application/friends_controller.dart';
import 'package:prostuti/features/friends/application/relationship_controller.dart';
import 'package:prostuti/features/friends/data/friend_models.dart';
import 'package:prostuti/features/friends/data/friends_repository.dart';
import 'package:prostuti/features/friends/data/relationship.dart';
import 'package:prostuti/features/profile/data/profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeRepo extends FriendsRepository {
  _FakeRepo(CachedFetcher cache)
    : super(
        SupabaseClient('http://localhost', 'anon', authOptions: const AuthClientOptions(autoRefreshToken: false)),
        cache,
      );

  final queries = <String>[];
  final delays = <String, Duration>{};

  @override
  Future<List<UserSearchResult>> search(String query, {int limit = 20}) async {
    queries.add(query);
    await Future<void>.delayed(delays[query] ?? Duration.zero);
    return [
      UserSearchResult(
        user: UserSummary(id: 'id-$query', username: query),
      ),
    ];
  }

  @override
  Future<Map<String, Relationship>> relationshipsFor(List<String> userIds) async => {
    for (final id in userIds) id: const Relationship(RelationshipStatus.requestReceived, requestId: 42),
  };
}

void main() {
  late _FakeRepo repo;
  late ProviderContainer container;

  setUp(() async {
    repo = _FakeRepo(CachedFetcher(await CacheStore.inMemory()));
    container = ProviderContainer(
      overrides: [friendsRepositoryProvider.overrideWithValue(repo), currentUserIdProvider.overrideWithValue('me')],
    );
    // Keep the auto-dispose notifier alive for the whole test.
    container.listen(userSearchProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  UserSearchNotifier notifier() => container.read(userSearchProvider.notifier);
  UserSearchState state() => container.read(userSearchProvider);

  test('queries shorter than 2 characters never hit the server', () async {
    notifier().onQueryChanged('a');
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(repo.queries, isEmpty);
    expect(state().tooShort, isTrue);
  });

  test('debounces typing: only the last query is searched', () async {
    notifier()
      ..onQueryChanged('ra')
      ..onQueryChanged('rah')
      ..onQueryChanged('rahim');
    expect(state().results.isLoading, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(repo.queries, ['rahim']);
    expect(state().results.value!.single.user.username, 'rahim');
  });

  test('a slow, outdated response never overwrites a newer one', () async {
    repo.delays['slow'] = const Duration(milliseconds: 300);
    notifier().onQueryChanged('slow');
    await Future<void>.delayed(const Duration(milliseconds: 420)); // request in flight
    notifier().onQueryChanged('fast');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(repo.queries, ['slow', 'fast']);
    expect(state().query, 'fast');
    expect(state().results.value!.single.user.username, 'fast');
  });

  test('seeds batched relationships so buttons render without extra calls', () async {
    notifier().onQueryChanged('karim');
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(
      container.read(relationshipSeedsProvider)['id-karim'],
      const Relationship(RelationshipStatus.requestReceived, requestId: 42),
    );
  });

  test('repeated queries are served from the in-memory cache', () async {
    notifier().onQueryChanged('nadia');
    await Future<void>.delayed(const Duration(milliseconds: 450));
    notifier()
      ..onQueryChanged('nad')
      ..onQueryChanged('nadia');
    expect(state().results.value, isNotNull, reason: 'cache hit is synchronous');
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(repo.queries, ['nadia']);
  });

  test('a seeded relationship builds synchronously', () async {
    container.read(relationshipSeedsProvider).put('u9', Relationship.friends);
    final sub = container.listen(relationshipProvider('u9'), (_, _) {});
    addTearDown(sub.close);
    expect(container.read(relationshipProvider('u9')).value, Relationship.friends);
  });

  test('my own id is always "self"', () {
    final sub = container.listen(relationshipProvider('me'), (_, _) {});
    addTearDown(sub.close);
    expect(container.read(relationshipProvider('me')).value, Relationship.self);
  });
}
