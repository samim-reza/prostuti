import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/features/exam/application/exam_clock.dart';

/// Manually advanced clock.
class FakeClock {
  FakeClock(this.now);
  DateTime now;
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

void main() {
  group('ExamTiming.format', () {
    test('mm:ss and h:mm:ss in Latin digits', () {
      expect(ExamTiming.format(const Duration(minutes: 5, seconds: 7), bangla: false), '05:07');
      expect(ExamTiming.format(const Duration(hours: 2), bangla: false), '2:00:00');
      expect(ExamTiming.format(Duration.zero, bangla: false), '00:00');
    });

    test('Bangla digits', () {
      expect(ExamTiming.format(const Duration(minutes: 12, seconds: 34), bangla: true), '১২:৩৪');
    });

    test('partial seconds round up so 00:00 only shows at the end', () {
      expect(ExamTiming.format(const Duration(milliseconds: 300), bangla: false), '00:01');
      expect(ExamTiming.format(const Duration(seconds: 59, milliseconds: 1), bangla: false), '01:00');
    });
  });

  group('ExamTiming.phaseOf', () {
    test('thresholds at 5 minutes and 1 minute', () {
      expect(ExamTiming.phaseOf(const Duration(minutes: 6)), TimerPhase.normal);
      expect(ExamTiming.phaseOf(const Duration(minutes: 5)), TimerPhase.warning);
      expect(ExamTiming.phaseOf(const Duration(seconds: 61)), TimerPhase.warning);
      expect(ExamTiming.phaseOf(const Duration(seconds: 60)), TimerPhase.critical);
      expect(ExamTiming.phaseOf(const Duration(seconds: 1)), TimerPhase.critical);
      expect(ExamTiming.phaseOf(Duration.zero), TimerPhase.expired);
    });

    test('remaining never goes negative', () {
      final now = DateTime(2026, 10, 4, 10);
      expect(ExamTiming.remaining(now.subtract(const Duration(seconds: 5)), now), Duration.zero);
    });

    test('duration follows the BCS pace with a 5-minute floor', () {
      expect(ExamTiming.forQuestions(200), const Duration(minutes: 120));
      expect(ExamTiming.forQuestions(5), const Duration(minutes: 5));
      expect(ExamTiming.forQuestions(5, withMinimum: false), const Duration(seconds: 180));
    });
  });

  group('ExamCountdown', () {
    late FakeClock clock;
    late List<TimerPhase> phases;
    late int expired;

    ExamCountdown make(Duration left) {
      final countdown = ExamCountdown(
        deadline: clock.now.add(left),
        now: clock.call,
        onPhaseChanged: phases.add,
        onExpired: () => expired++,
        interval: const Duration(days: 1), // ticks are driven manually
      );
      addTearDown(countdown.dispose);
      return countdown;
    }

    setUp(() {
      clock = FakeClock(DateTime(2026, 10, 4, 10));
      phases = [];
      expired = 0;
    });

    test('warns once at 5 minutes and once at 1 minute, then auto-submits once', () {
      final c = make(const Duration(minutes: 6))..start();
      expect(phases, isEmpty);
      expect(c.remaining.value, const Duration(minutes: 6));

      clock.advance(const Duration(seconds: 61));
      c.tick();
      expect(phases, [TimerPhase.warning]);
      clock.advance(const Duration(seconds: 30));
      c.tick();
      expect(phases, [TimerPhase.warning], reason: 'no repeat within a phase');

      clock.advance(const Duration(minutes: 3, seconds: 30));
      c.tick();
      expect(phases, [TimerPhase.warning, TimerPhase.critical]);
      expect(expired, 0);

      clock.advance(const Duration(seconds: 59));
      c.tick();
      expect(expired, 1);
      expect(c.isExpired, isTrue);
      expect(c.remaining.value, Duration.zero);

      clock.advance(const Duration(seconds: 10));
      c.tick();
      expect(expired, 1, reason: 'auto-submit fires exactly once');
    });

    test('resuming after the deadline triggers auto-submit immediately', () {
      final c = make(const Duration(seconds: -30))..start();
      expect(expired, 1);
      expect(phases, isEmpty);
      expect(c.isExpired, isTrue);
    });

    test('resuming inside the last minute shows only the critical alert', () {
      make(const Duration(seconds: 40)).start();
      expect(phases, [TimerPhase.critical]);
      expect(expired, 0);
    });

    test('a long background pause jumps straight to expiry', () {
      final c = make(const Duration(minutes: 30))..start();
      clock.advance(const Duration(hours: 1));
      c.tick();
      expect(expired, 1);
    });
  });
}
