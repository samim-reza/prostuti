import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/config/app_settings.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/features/study_plan/application/plan_providers.dart' show ProviderReader;
import 'package:prostuti/features/study_plan/application/swr_notifier.dart';
import 'package:prostuti/features/study_plan/data/daily_advice_models.dart';
import 'package:prostuti/features/study_plan/data/daily_advice_repository.dart';
import 'package:prostuti/features/study_plan/data/study_plan_repository.dart' show Peeked;

/// Today's AI advice in the UI language (stale-while-revalidate; rebuilt on
/// sign-in/out and when the language changes).
class DailyAdviceNotifier extends SwrNotifier<DailyAdvice> {
  DailyAdviceRepository get _repo => ref.read(dailyAdviceRepositoryProvider);

  String get _locale => ref.read(appSettingsProvider).locale.languageCode == 'en' ? 'en' : 'bn';

  @override
  FutureOr<DailyAdvice> build() {
    ref.watch(appSettingsProvider.select((s) => s.locale.languageCode));
    return super.build();
  }

  @override
  Peeked<DailyAdvice>? peek() => _repo.peek(_locale);

  @override
  Future<DailyAdvice> load({bool force = false}) => _repo.advice(_locale, force: force);

  /// Asks the server to re-evaluate today's advice (refresh button). Keeps
  /// the current advice on screen meanwhile; rethrows failures (offline,
  /// `rate_limited` after 3 refreshes a day) for the caller to report.
  Future<DailyAdvice> regenerate() async {
    final busy = ref.read(dailyAdviceRefreshingProvider.notifier);
    final current = state.value;
    if (busy.running && current != null) return current;
    busy.running = true;
    try {
      final advice = await _repo.regenerate(_locale);
      if (ref.mounted) state = AsyncData(advice);
      return advice;
    } finally {
      busy.running = false;
    }
  }
}

final dailyAdviceProvider = AsyncNotifierProvider<DailyAdviceNotifier, DailyAdvice>(DailyAdviceNotifier.new);

/// True while a refresh of the advice is running (small spinner on the card).
class DailyAdviceRefreshingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  bool get running => state;

  set running(bool value) => state = value;
}

final dailyAdviceRefreshingProvider = NotifierProvider<DailyAdviceRefreshingNotifier, bool>(
  DailyAdviceRefreshingNotifier.new,
);

/// Refreshes the advice after the learner's data changed (e.g. an exam was
/// submitted). Works with `ref.read` and `container.read`; never throws.
///
/// With [regenerate] (default) the server re-evaluates today's advice — cheap
/// when nothing relevant changed (it compares a signature and answers with
/// the stored advice without spending one of the 3 daily refreshes).
/// Without it, today's stored advice is only re-read.
Future<void> refreshDailyAdvice(ProviderReader read, {bool regenerate = true}) async {
  try {
    // Let the first load settle so it cannot overwrite a newer answer.
    await read(dailyAdviceProvider.future);
    final notifier = read(dailyAdviceProvider.notifier);
    if (regenerate && ConnectivityService.instance.isOnline) {
      await notifier.regenerate();
    } else {
      await notifier.refresh();
    }
  } on Object {
    // Background refresh: keep what is on screen.
  }
}
