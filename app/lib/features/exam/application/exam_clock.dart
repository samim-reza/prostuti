import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:prostuti/core/utils/formatters.dart';

/// Injectable clock (tests pass a fake one).
typedef NowFn = DateTime Function();

/// Countdown phases: amber from 5 minutes, red in the last minute.
enum TimerPhase { normal, warning, critical, expired }

abstract final class ExamTiming {
  static const warningAt = Duration(minutes: 5);
  static const criticalAt = Duration(minutes: 1);

  /// BCS pace: 200 questions in 120 minutes → 36 s per question.
  static const secondsPerQuestion = 36;

  /// Minimum duration the server grants to short exams.
  static const minimumSeconds = 300;

  static Duration remaining(DateTime deadline, DateTime now) {
    final d = deadline.difference(now);
    return d.isNegative ? Duration.zero : d;
  }

  static TimerPhase phaseOf(Duration remaining) {
    if (remaining <= Duration.zero) return TimerPhase.expired;
    if (remaining <= criticalAt) return TimerPhase.critical;
    if (remaining <= warningAt) return TimerPhase.warning;
    return TimerPhase.normal;
  }

  /// `mm:ss` (or `h:mm:ss`) in Bangla or Latin digits. Rounds partial
  /// seconds **up** so the display never shows 00:00 while time remains.
  static String format(Duration remaining, {required bool bangla}) {
    final ms = remaining.inMilliseconds;
    final seconds = ms <= 0 ? 0 : (ms / 1000).ceil();
    return Fmt.clock(Duration(seconds: seconds), bangla: bangla);
  }

  /// Duration the server allots for an exam of [questions] questions.
  static Duration forQuestions(int questions, {bool withMinimum = true}) {
    final secs = questions * secondsPerQuestion;
    return Duration(seconds: withMinimum && secs < minimumSeconds ? minimumSeconds : secs);
  }
}

/// Drives the exam timer from the session deadline (never from a counter,
/// so backgrounding the app or a janky frame can't drift the clock).
///
/// * [remaining] is a [ValueNotifier] → only the timer widget rebuilds;
/// * [onPhaseChanged] fires once per transition (5-minute / 1-minute alerts);
/// * [onExpired] fires exactly once when time runs out (auto-submit).
class ExamCountdown {
  ExamCountdown({
    required this.deadline,
    NowFn? now,
    this.onPhaseChanged,
    this.onExpired,
    this.interval = const Duration(seconds: 1),
  }) : _now = now ?? DateTime.now,
       remaining = ValueNotifier(ExamTiming.remaining(deadline, (now ?? DateTime.now)()));

  final DateTime deadline;
  final NowFn _now;
  final void Function(TimerPhase phase)? onPhaseChanged;
  final VoidCallback? onExpired;
  final Duration interval;
  final ValueNotifier<Duration> remaining;

  TimerPhase _phase = TimerPhase.normal;
  bool _expiredFired = false;
  Timer? _timer;

  TimerPhase get phase => _phase;
  bool get isExpired => _expiredFired;

  void start() {
    tick();
    if (_expiredFired) return;
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => tick());
  }

  /// Recomputes the remaining time (also call on app resume).
  void tick() {
    if (_expiredFired) return;
    final left = ExamTiming.remaining(deadline, _now());
    remaining.value = left;
    final next = ExamTiming.phaseOf(left);
    if (next != _phase) {
      _phase = next;
      if (next != TimerPhase.expired) onPhaseChanged?.call(next);
    }
    if (next == TimerPhase.expired) {
      _expiredFired = true;
      _timer?.cancel();
      onExpired?.call();
    }
  }

  void stop() => _timer?.cancel();

  void dispose() {
    _timer?.cancel();
    remaining.dispose();
  }
}
