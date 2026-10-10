import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/core/services/error_reporter.dart';

/// A non-symbolic stack as printed by obfuscated `--split-debug-info` builds.
StackTrace _obfuscated({required String pid, required String abs, String virt = '00000000002e7b2f'}) =>
    StackTrace.fromString('''
*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
pid: $pid, tid: 7321, name 1.ui
os: android arch: arm64 comp: yes sim: no
build_id: '3c1b2e0f9a8d7c6b5a4f3e2d1c0b9a87'
isolate_dso_base: 7a1c000000, vm_dso_base: 7a1c000000
    #00 abs $abs virt $virt _kDartIsolateSnapshotInstructions+0x2a0b2f
    #01 abs 0000007a1c4e1000 virt 0000000000301000 _kDartIsolateSnapshotInstructions+0x2ba000
''');

StackTrace _symbolic(String top) => StackTrace.fromString('''
#0      $top (package:prostuti/features/exam/exam.dart:12:5)
#1      ExamScreen.build (package:prostuti/features/exam/exam_screen.dart:40:7)
<asynchronous suspension>
#2      main (package:prostuti/main.dart:3:1)
''');

ErrorReporter _reporter(List<Map<String, Object?>> sent, {int max = 20, ErrorSink? sink}) =>
    ErrorReporter(enabled: true, maxPerSession: max, appInfo: () async => {'p_app_version': '1.2.3'})
      ..routeResolver = (() => '/exam/:id')
      ..localeResolver = (() => 'bn')
      ..attach(
        sink ??
            (params) async {
              sent.add(params);
            },
      );

void main() {
  group('fingerprint', () {
    test('same error type and frames → same fingerprint, regardless of message', () {
      final a = errorFingerprint(StateError('one'), _symbolic('Exam.start'));
      final b = errorFingerprint(StateError('two'), _symbolic('Exam.start'));
      expect(a, b);
      expect(a, hasLength(32));
    });

    test('different top frame or error type → different fingerprint', () {
      final base = errorFingerprint(StateError('x'), _symbolic('Exam.start'));
      expect(errorFingerprint(StateError('x'), _symbolic('Exam.finish')), isNot(base));
      expect(errorFingerprint(ArgumentError('x'), _symbolic('Exam.start')), isNot(base));
    });

    test('obfuscated stacks ignore pid and absolute (ASLR) addresses', () {
      final a = errorFingerprint(StateError('x'), _obfuscated(pid: '100', abs: '0000007a1c4e7b2f'));
      final b = errorFingerprint(StateError('x'), _obfuscated(pid: '999', abs: '0000007b99887b2f'));
      final other = errorFingerprint(StateError('x'), _obfuscated(pid: '1', abs: '1', virt: '0000000000000abc'));
      expect(a, b);
      expect(other, isNot(a));
      expect(topStackFrames(_obfuscated(pid: '1', abs: 'ff')).first, startsWith('virt 00000000002e7b2f'));
    });

    test('without a stack, the message with numbers masked is used', () {
      expect(errorFingerprint(StateError('index 3 of 10'), null), errorFingerprint(StateError('index 7 of 12'), null));
      expect(errorFingerprint(StateError('index 3'), null), isNot(errorFingerprint(StateError('missing'), null)));
    });

    test('takes at most the requested number of frames', () {
      expect(topStackFrames(_symbolic('A.b'), count: 2), hasLength(2));
      expect(topStackFrames(null), isEmpty);
    });
  });

  group('scrubbing & clipping', () {
    test('masks tokens, emails and phone numbers', () {
      const raw =
          'GET https://x.supabase.co/a?token=abc123&x=1 failed for rahim.k@example.com '
          'Authorization: Bearer eyJhbGciOiJI.eyJzdWIiOiIx.c2lnbmF0dXJl phone 01712345678';
      final out = scrubSensitive(raw);
      expect(out, isNot(contains('abc123')));
      expect(out, isNot(contains('rahim.k@example.com')));
      expect(out, isNot(contains('eyJhbGciOiJI')));
      expect(out, isNot(contains('01712345678')));
      expect(out, contains('token=<redacted>'));
      expect(out, contains('<email>'));
      expect(out, contains('<phone>'));
      expect(scrubSensitive('package:prostuti/main.dart:12:5'), 'package:prostuti/main.dart:12:5');
      expect(scrubSensitive('call +8801912345678 now'), 'call <phone> now');
      // Obfuscated frames must survive untouched for `flutter symbolize`.
      const frame = '#00 abs 0000007a01712345678f virt 0000000001712345678 _kDartIsolateSnapshotInstructions+0x2a0b2f';
      expect(scrubSensitive(frame), frame);
    });

    test('clip respects limits, NULs and surrogate pairs', () {
      expect(clip(null, 5), isNull);
      expect(clip('abc', 5), 'abc');
      expect(clip('a\u0000bcdef', 3), 'abc');
      expect(clip('ab😀', 3), 'ab'); // never half an emoji
      expect(clip('x' * 2000, 1000), hasLength(1000));
    });
  });

  group('session gate', () {
    test('each fingerprint once, capped per session', () {
      final gate = ErrorReportGate(maxPerSession: 3);
      expect(gate.admit('a'), isTrue);
      expect(gate.admit('a'), isFalse);
      expect(gate.admit('b'), isTrue);
      expect(gate.admit('c'), isTrue);
      expect(gate.admit('d'), isFalse);
      expect(gate.admitted, 3);
    });
  });

  group('reporter', () {
    test('sends one report per distinct error with context', () async {
      final sent = <Map<String, Object?>>[];
      final reporter = _reporter(sent)
        ..record(StateError('boom'), _symbolic('A.b'), fatal: true)
        ..record(StateError('boom again'), _symbolic('A.b'), fatal: true)
        ..record(StateError('other'), _symbolic('C.d'));
      await pumpEventQueue();
      expect(sent, hasLength(2));
      final first = sent.first;
      expect(first['p_error'], 'StateError: Bad state: boom');
      expect(first['p_fatal'], isTrue);
      expect(first['p_route'], '/exam/:id');
      expect(first['p_locale'], 'bn');
      expect(first['p_app_version'], '1.2.3');
      expect(first['p_platform'], defaultTargetPlatform.name);
      expect(first['p_fingerprint'], errorFingerprint(StateError('x'), _symbolic('A.b')));
      expect(first['p_stack'], contains('A.b'));
      expect(reporter.enabled, isTrue);
    });

    test('stops after the per-session limit', () async {
      final sent = <Map<String, Object?>>[];
      final reporter = _reporter(sent, max: 3);
      for (var i = 0; i < 10; i++) {
        reporter.record(StateError('e$i'), _symbolic('F$i.run'));
      }
      await pumpEventQueue();
      expect(sent, hasLength(3));
    });

    test('network errors are not reported', () async {
      final sent = <Map<String, Object?>>[];
      _reporter(sent)
        ..record(const SocketException('Failed host lookup'), _symbolic('Net.get'))
        ..record(TimeoutException('slow'), _symbolic('Net.get'));
      await pumpEventQueue();
      expect(sent, isEmpty);
    });

    test('a failing or hanging transport never throws', () async {
      final failing = ErrorReporter(enabled: true, appInfo: () async => const {})
        ..attach((_) async => throw StateError('server down'));
      expect(() => failing.record(StateError('x'), null), returnsNormally);

      final hanging = ErrorReporter(
        enabled: true,
        timeout: const Duration(milliseconds: 20),
        appInfo: () => Completer<Map<String, String>>().future,
      )..attach((_) => Completer<void>().future);
      expect(() => hanging.record(StateError('y'), null), returnsNormally);
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });

    test('reports captured before attach are sent once a transport exists', () async {
      final sent = <Map<String, Object?>>[];
      final reporter = ErrorReporter(enabled: true, appInfo: () async => const {})
        ..record(StateError('early'), _symbolic('Boot.run'));
      await pumpEventQueue();
      expect(sent, isEmpty);
      reporter.attach((params) async => sent.add(params));
      await pumpEventQueue();
      expect(sent, hasLength(1));
      expect(sent.single['p_error'], contains('early'));
    });

    test('disabled reporter (debug builds) does nothing', () async {
      final sent = <Map<String, Object?>>[];
      ErrorReporter(enabled: false)
        ..attach((params) async => sent.add(params))
        ..record(StateError('x'), null);
      await pumpEventQueue();
      expect(sent, isEmpty);
    });

    test('flutter errors carry library and context; silent ones are skipped', () async {
      final sent = <Map<String, Object?>>[];
      _reporter(sent)
        ..recordFlutterError(
          FlutterErrorDetails(
            exception: StateError('layout'),
            stack: _symbolic('RenderBox.layout'),
            library: 'rendering library',
            context: ErrorDescription('during performLayout()'),
          ),
        )
        ..recordFlutterError(
          FlutterErrorDetails(exception: StateError('quiet'), stack: _symbolic('Quiet.run'), silent: true),
        );
      await pumpEventQueue();
      expect(sent, hasLength(1));
      expect(sent.single['p_context'], 'rendering library: during performLayout()');
      expect(sent.single['p_fatal'], isFalse);
    });
  });
}
