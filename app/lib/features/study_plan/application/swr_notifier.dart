import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/features/study_plan/data/study_plan_repository.dart';

/// Stale-while-revalidate [AsyncNotifier]:
///
/// * the first build returns the cached value **synchronously** (even when
///   stale) so screens paint instantly on a cold start, then revalidates in
///   the background;
/// * without a cache it fetches normally (skeleton → data);
/// * [refresh] forces a network round trip but keeps the current data on
///   screen while it runs (no flicker) and rethrows so pull-to-refresh can
///   report failures.
abstract class SwrNotifier<T> extends AsyncNotifier<T> {
  Peeked<T>? peek();

  Future<T> load({bool force = false});

  @override
  FutureOr<T> build() {
    // Re-run for a different user (sign-out/in) — caches are keyed per user.
    ref.watch(currentUserIdProvider);
    final cached = peek();
    if (cached != null) {
      if (!cached.fresh) unawaited(Future.microtask(_revalidate));
      return cached.value;
    }
    return load();
  }

  Future<void> _revalidate() async {
    try {
      await refresh();
    } on Object {
      // Background revalidation: keep showing cached data.
    }
  }

  Future<void> refresh() async {
    try {
      final value = await load(force: true);
      if (ref.mounted) state = AsyncData(value);
    } on Object catch (e, st) {
      if (ref.mounted && !state.hasValue) state = AsyncError(e, st);
      rethrow;
    }
  }
}
