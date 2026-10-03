import 'dart:async';

import 'package:flutter/foundation.dart';

/// Runs the latest action only after [delay] of silence (search boxes).
class Debouncer {
  Debouncer(this.delay);
  final Duration delay;
  Timer? _timer;

  void call(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() => _timer?.cancel();
}

/// Runs at most once per [interval]; the trailing call is kept so the final
/// state always wins (reaction taps, typing indicators).
class Throttler {
  Throttler(this.interval);
  final Duration interval;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _trailing;

  void call(VoidCallback action) {
    final now = DateTime.now();
    final elapsed = now.difference(_last);
    _trailing?.cancel();
    if (elapsed >= interval) {
      _last = now;
      action();
    } else {
      _trailing = Timer(interval - elapsed, () {
        _last = DateTime.now();
        action();
      });
    }
  }

  void dispose() => _trailing?.cancel();
}

/// Client-side token bucket mirroring the server limits, so a spamming user
/// gets instant feedback instead of a round-trip that ends in HTTP 429.
class TokenBucket {
  TokenBucket({required this.capacity, required this.refillEvery}) : _tokens = capacity.toDouble();

  final int capacity;
  final Duration refillEvery;
  double _tokens;
  DateTime _lastRefill = DateTime.now();

  bool tryTake() {
    final now = DateTime.now();
    final refill = now.difference(_lastRefill).inMicroseconds / refillEvery.inMicroseconds;
    _tokens = (_tokens + refill).clamp(0, capacity.toDouble());
    _lastRefill = now;
    if (_tokens < 1) return false;
    _tokens -= 1;
    return true;
  }
}
