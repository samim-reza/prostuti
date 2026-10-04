import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:prostuti/core/config/env.dart';

/// How a rewarded-ad request ended.
enum RewardedOutcome {
  /// Watched to the end.
  earned,

  /// Closed before the reward.
  skipped,

  /// No ad to show (no fill, ad blocker/Private DNS, load timeout, SDK
  /// error). Not the user's fault, so callers don't hold the reward back.
  unavailable,
}

/// Rewarded ads ("watch an ad to download today's notes").
///
/// Uses Google's official test unit ids unless real ids are provided via
/// `--dart-define` (or remote config), so test builds never serve live ads.
class AdsService {
  AdsService._();
  static final instance = AdsService._();

  static const _testRewardedAndroid = 'ca-app-pub-3940256099942544/5224354917';
  static const _testRewardedIos = 'ca-app-pub-3940256099942544/1712485313';

  bool _initialized = false;
  RewardedAd? _preloaded;
  bool _loading = false;

  bool get isSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  String _unitId({String? remoteAndroid, String? remoteIos}) {
    if (Platform.isIOS) {
      final id = (remoteIos?.isNotEmpty ?? false) ? remoteIos! : Env.admobRewardedIos;
      return id.isEmpty ? _testRewardedIos : id;
    }
    final id = (remoteAndroid?.isNotEmpty ?? false) ? remoteAndroid! : Env.admobRewardedAndroid;
    return id.isEmpty ? _testRewardedAndroid : id;
  }

  Future<void> init() async {
    if (!isSupported || _initialized) return;
    _initialized = true;
    await MobileAds.instance.initialize();
  }

  /// Loads an ad in the background so it's ready the moment the user taps.
  void preload({String? remoteAndroid, String? remoteIos}) {
    if (!isSupported || _preloaded != null || _loading) return;
    _loading = true;
    unawaited(
      RewardedAd.load(
        adUnitId: _unitId(remoteAndroid: remoteAndroid, remoteIos: remoteIos),
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _preloaded = ad;
            _loading = false;
          },
          onAdFailedToLoad: (_) => _loading = false,
        ),
      ),
    );
  }

  /// Shows a rewarded ad and reports how it ended.
  Future<RewardedOutcome> showRewarded({String? remoteAndroid, String? remoteIos}) async {
    if (!isSupported) return RewardedOutcome.earned; // web/desktop builds: no ads
    final RewardedAd? ad;
    try {
      await init();
      ad = _preloaded ?? await _loadNow(remoteAndroid: remoteAndroid, remoteIos: remoteIos);
    } on Object {
      return RewardedOutcome.unavailable;
    } finally {
      _preloaded = null;
    }
    if (ad == null) return RewardedOutcome.unavailable;

    final completer = Completer<RewardedOutcome>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        unawaited(ad.dispose());
        if (!completer.isCompleted) completer.complete(earned ? RewardedOutcome.earned : RewardedOutcome.skipped);
        preload(remoteAndroid: remoteAndroid, remoteIos: remoteIos);
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        unawaited(ad.dispose());
        if (!completer.isCompleted) completer.complete(RewardedOutcome.unavailable);
      },
    );
    try {
      await ad.show(onUserEarnedReward: (_, _) => earned = true);
    } on Object {
      unawaited(ad.dispose());
      return RewardedOutcome.unavailable;
    }
    return completer.future;
  }

  Future<RewardedAd?> _loadNow({String? remoteAndroid, String? remoteIos}) {
    final completer = Completer<RewardedAd?>();
    unawaited(
      RewardedAd.load(
        adUnitId: _unitId(remoteAndroid: remoteAndroid, remoteIos: remoteIos),
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: completer.complete,
          onAdFailedToLoad: (_) => completer.complete(null),
        ),
      ),
    );
    return completer.future.timeout(const Duration(seconds: 20), onTimeout: () => null);
  }
}

final adsServiceProvider = Provider<AdsService>((ref) => AdsService.instance);
