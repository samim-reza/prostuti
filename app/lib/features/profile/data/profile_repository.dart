import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/cache/cached_fetcher.dart';
import 'package:prostuti/core/config/app_constants.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/network/rpc.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/offline/offline_queue.dart';
import 'package:prostuti/features/profile/data/profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileRepository {
  ProfileRepository(this._client, this._cache);

  final SupabaseClient _client;
  final CachedFetcher _cache;

  static String _key(String id) => 'profile:$id';

  String? get _uid => _client.auth.currentUser?.id;

  Future<Profile?> fetchMe({bool force = false}) async {
    final uid = _uid;
    if (uid == null) return null;
    return fetchById(uid, force: force);
  }

  /// Cached 5 minutes; "not found" is negatively cached for 2 minutes so a
  /// deleted/unknown profile id can't be used to hammer the database.
  Future<Profile?> fetchById(String id, {bool force = false}) {
    return _cache.get<Profile?>(
      _key(id),
      forceRefresh: force,
      fetch: () async {
        final row = await guard(() => _client.from('profiles').select(Profile.columns).eq('id', id).maybeSingle());
        return row == null ? null : Profile.fromJson(row);
      },
      encode: (p) => p?.toJson(),
      decode: (j) => j == null ? null : Profile.fromJson(Map<String, dynamic>.from(j as Map)),
      policy: const CachePolicy(ttl: Duration(minutes: 5)),
      isEmpty: (p) => p == null,
    );
  }

  Future<Profile> updateMe(Map<String, dynamic> patch) async {
    final uid = _uid;
    if (uid == null) throw const AuthFailure('not_authenticated');
    final row = await guard(
      () => _client.from('profiles').update(patch).eq('id', uid).select(Profile.columns).single(),
    );
    final profile = Profile.fromJson(row);
    await _cache.store.write(_key(uid), profile.toJson(), const Duration(minutes: 5));
    return profile;
  }

  Future<bool> isUsernameAvailable(String username) async {
    final row = await guard(() => _client.from('profiles').select('id').eq('username', username.trim()).maybeSingle());
    return row == null || row['id'] == _uid;
  }

  /// Uploads an already-compressed WebP avatar and stores its public URL.
  Future<Profile> uploadAvatar(Uint8List webpBytes) async {
    final uid = _uid;
    if (uid == null) throw const AuthFailure('not_authenticated');
    final path = '$uid/avatar_${DateTime.now().millisecondsSinceEpoch}.webp';
    await guard(
      () => _client.storage
          .from(AppConstants.avatarsBucket)
          .uploadBinary(
            path,
            webpBytes,
            fileOptions: const FileOptions(contentType: 'image/webp', cacheControl: '31536000'),
          ),
    );
    final url = _client.storage.from(AppConstants.avatarsBucket).getPublicUrl(path);
    return updateMe({'avatar_url': url});
  }

  Future<Map<String, dynamic>> fetchPrivate() async {
    final uid = _uid;
    if (uid == null) return const {};
    final row = await guard(() => _client.from('user_private').select().eq('user_id', uid).maybeSingle());
    return row ?? const {};
  }

  Future<void> updatePrivate(Map<String, dynamic> patch) async {
    final uid = _uid;
    if (uid == null) return;
    await guard(() => _client.from('user_private').upsert({'user_id': uid, ...patch}));
  }

  Future<Map<String, dynamic>> relationship(String userId) =>
      _client.rpcMap('get_relationship', params: {'p_user': userId});

  Future<void> invalidate(String id) => _cache.invalidate(_key(id));

  /// Offline-queue operation: `profiles` update with a patch of granted
  /// columns. Idempotent, so replays after a lost response are harmless.
  static const offlineUpdateOp = 'profile.update';

  /// Merges [patch] into [current] and writes it to the cache, so an edit made
  /// offline shows everywhere (and survives a restart) until it syncs.
  Future<Profile> applyLocalPatch(Profile current, Map<String, dynamic> patch) async {
    final merged = Profile.fromJson({...current.toJson(), ...patch});
    await _cache.store.write(_key(current.id), merged.toJson(), const Duration(minutes: 5));
    return merged;
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final repo = ProfileRepository(ref.watch(supabaseProvider), ref.watch(cachedFetcherProvider));
  OfflineQueue.instance.register(ProfileRepository.offlineUpdateOp, (patch) async {
    await repo.updateMe(patch);
  });
  return repo;
});

/// The signed-in user's profile. `null` when signed out.
class CurrentProfileNotifier extends AsyncNotifier<Profile?> {
  @override
  Future<Profile?> build() async {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return null;
    return ref.read(profileRepositoryProvider).fetchMe();
  }

  Future<void> reload() async {
    state = AsyncData(await ref.read(profileRepositoryProvider).fetchMe(force: true));
  }

  Future<Profile> save(Map<String, dynamic> patch) async {
    final updated = await ref.read(profileRepositoryProvider).updateMe(patch);
    state = AsyncData(updated);
    return updated;
  }

  /// Offline-first save: shown immediately (UI + cache), sent now when online
  /// or queued until the connection returns. Returns true once synced.
  /// Reverts and rethrows when the server rejects the change.
  Future<bool> saveOfflineFirst(Map<String, dynamic> patch) async {
    final repo = ref.read(profileRepositoryProvider);
    final previous = state.value;
    if (previous != null) state = AsyncData(await repo.applyLocalPatch(previous, patch));
    try {
      return await OfflineQueue.instance.run(ProfileRepository.offlineUpdateOp, patch);
    } on Object {
      if (previous != null && ref.mounted) state = AsyncData(await repo.applyLocalPatch(previous, const {}));
      rethrow;
    }
  }

  Future<Profile> uploadAvatar(Uint8List bytes) async {
    final updated = await ref.read(profileRepositoryProvider).uploadAvatar(bytes);
    state = AsyncData(updated);
    return updated;
  }

  Future<void> setOnboardingStep(OnboardingStep step) => save({'onboarding_step': step.name});
}

final currentProfileProvider = AsyncNotifierProvider<CurrentProfileNotifier, Profile?>(CurrentProfileNotifier.new);

/// Any user's profile (cached).
final profileByIdProvider = FutureProvider.autoDispose.family<Profile?, String>(
  (ref, id) => ref.watch(profileRepositoryProvider).fetchById(id),
);
