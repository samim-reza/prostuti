import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/cache/cache_store.dart';
import 'package:prostuti/core/cache/cached_fetcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The Supabase client. Initialised once in `bootstrap()`.
final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

/// Opened in `bootstrap()` and injected with `overrideWithValue`.
final cacheStoreProvider = Provider<CacheStore>(
  (ref) => throw UnimplementedError('cacheStoreProvider must be overridden in bootstrap'),
);

final cachedFetcherProvider = Provider<CachedFetcher>((ref) => CachedFetcher(ref.watch(cacheStoreProvider)));

/// Emits on every sign-in / sign-out / token refresh.
final authStateProvider = StreamProvider<AuthState>((ref) => ref.watch(supabaseProvider).auth.onAuthStateChange);

/// Current session user id (null when signed out). Rebuilds on auth changes.
final currentUserIdProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(supabaseProvider).auth.currentUser?.id;
});
