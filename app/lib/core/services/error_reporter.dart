import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:prostuti/core/errors/failure.dart';

/// Delivers one report (the `log_client_error` RPC parameters).
typedef ErrorSink = Future<void> Function(Map<String, Object?> params);

/// Crash / error reporting without a third-party SDK.
///
/// Release builds send uncaught errors to the `log_client_error` RPC
/// (`supabase/migrations/20261004000019_client_errors.sql`). Reporting is
/// fire-and-forget: it never throws, never blocks start-up, sends each
/// distinct error at most once per session and at most `maxPerSession`
/// reports in total. Offline / network errors are expected and not reported.
///
/// Stacks of obfuscated release builds are symbolized with the
/// `prostuti-debug-symbols-<run>` CI artifact (see `docs/RELEASE.md`).
class ErrorReporter {
  ErrorReporter({
    bool? enabled,
    int maxPerSession = 20,
    this.timeout = const Duration(seconds: 10),
    Future<Map<String, String>> Function()? appInfo,
  }) : enabled = enabled ?? kReleaseMode,
       _gate = ErrorReportGate(maxPerSession: maxPerSession),
       _appInfoLoader = appInfo ?? _packageInfo;

  static final instance = ErrorReporter();

  /// Reports are only collected in release builds (debug builds print).
  final bool enabled;
  final Duration timeout;
  final ErrorReportGate _gate;
  final Future<Map<String, String>> Function() _appInfoLoader;

  /// Current screen (e.g. `/exam/:id`), resolved lazily when an error occurs.
  String? Function()? routeResolver;

  /// The app's UI language, resolved lazily when an error occurs.
  String? Function()? localeResolver;

  ErrorSink? _sink;
  Future<Map<String, String>>? _appInfo;
  bool _recording = false;

  /// Reports captured before [attach] (e.g. while Supabase starts).
  final _pending = <Map<String, Object?>>[];
  static const _maxPending = 5;

  /// Connects the transport; anything captured earlier is sent now.
  void attach(ErrorSink sink) {
    _sink = sink;
    if (_pending.isEmpty) return;
    final queued = List.of(_pending);
    _pending.clear();
    for (final report in queued) {
      unawaited(_deliver(report));
    }
  }

  /// Hook for `FlutterError.onError`. Framework errors are caught by Flutter
  /// and the app keeps running, so they are recorded as non-fatal.
  void recordFlutterError(FlutterErrorDetails details) {
    if (details.silent) return;
    final library = details.library;
    final description = details.context?.toDescription();
    record(
      details.exception,
      details.stack,
      context: [?library, ?description].join(': '),
      message: details.exceptionAsString(),
    );
  }

  /// Records [error]. Safe to call from any error handler: never throws.
  void record(Object error, StackTrace? stack, {bool fatal = false, String? context, String? message}) {
    if (!enabled || _recording) return;
    _recording = true;
    try {
      if (isExpectedError(error)) return;
      final fingerprint = errorFingerprint(error, stack, message: message);
      if (!_gate.admit(fingerprint)) return;
      final report = <String, Object?>{
        'p_error': clip(scrubSensitive('${error.runtimeType}: ${message ?? _describe(error)}'), 1000),
        'p_fingerprint': fingerprint,
        'p_stack': stack == null ? null : clip(scrubSensitive(stack.toString()), 8000),
        'p_fatal': fatal,
        'p_platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'p_os': _os(),
        'p_locale': _safe(localeResolver) ?? PlatformDispatcher.instance.locale.toLanguageTag(),
        'p_route': clip(_safe(routeResolver), 200),
        'p_context': clip(context == null || context.isEmpty ? null : scrubSensitive(context), 300),
      };
      unawaited(_deliver(report));
    } on Object {
      // Reporting must never become a new source of errors.
    } finally {
      _recording = false;
    }
  }

  Future<void> _deliver(Map<String, Object?> report) async {
    try {
      final info = await (_appInfo ??= _appInfoLoader()).timeout(timeout, onTimeout: () => const {});
      report.addAll(info);
      final sink = _sink;
      if (sink == null) {
        if (_pending.length < _maxPending) _pending.add(report);
        return;
      }
      await sink(report).timeout(timeout);
    } on Object {
      // Offline, rate-limited or server down: the report is simply dropped.
    }
  }

  static String _describe(Object error) {
    try {
      return error.toString();
    } on Object {
      return '<unprintable>';
    }
  }

  static String? _safe(String? Function()? resolver) {
    try {
      return resolver?.call();
    } on Object {
      return null;
    }
  }

  static String? _os() {
    if (kIsWeb) return null;
    try {
      return clip('${Platform.operatingSystem} ${Platform.operatingSystemVersion}', 160);
    } on Object {
      return null;
    }
  }

  static Future<Map<String, String>> _packageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return {'p_app_version': info.version, 'p_build_number': info.buildNumber};
    } on Object {
      return const {};
    }
  }
}

/// Per-session limits: each fingerprint once, at most [maxPerSession] total.
class ErrorReportGate {
  ErrorReportGate({this.maxPerSession = 20});

  final int maxPerSession;
  final _seen = <String>{};

  int get admitted => _seen.length;

  /// True when a report with [fingerprint] should be sent.
  bool admit(String fingerprint) {
    if (_seen.length >= maxPerSession || _seen.contains(fingerprint)) return false;
    _seen.add(fingerprint);
    return true;
  }
}

/// Errors that are part of normal operation (offline, timeouts) and would
/// only drown real crashes.
bool isExpectedError(Object error) => AppFailure.from(error) is NetworkFailure;

/// Stable id of an error: its type plus the top [frames] stack frames.
///
/// Works for symbolic stacks (`#0 Foo.bar (package:…:12:5)`) and for the
/// non-symbolic stacks of obfuscated release builds, whose per-process
/// absolute addresses and header lines (pid, tid) are ignored. Without a
/// stack, the message (numbers masked) stands in for the frames.
String errorFingerprint(Object error, StackTrace? stack, {String? message, int frames = 5}) {
  final top = topStackFrames(stack, count: frames);
  final tail = top.isNotEmpty
      ? top.join('|')
      : clip((message ?? ErrorReporter._describe(error)).replaceAll(RegExp(r'\d+'), '#'), 200)!;
  return sha256.convert(utf8.encode('${error.runtimeType}|$tail')).toString().substring(0, 32);
}

final _frameLine = RegExp(r'^\s*#\d+\s+(.+)$');
final _absoluteAddress = RegExp(r'\babs\s+[0-9a-fA-F]+\s*');

/// The first [count] frames of [stack], normalized for fingerprinting.
List<String> topStackFrames(StackTrace? stack, {int count = 5}) {
  if (stack == null) return const [];
  final frames = <String>[];
  for (final line in stack.toString().split('\n')) {
    final match = _frameLine.firstMatch(line);
    if (match == null) continue;
    final frame = match.group(1)!.replaceAll(_absoluteAddress, '').trim();
    if (frame.isEmpty) continue;
    frames.add(frame);
    if (frames.length == count) break;
  }
  return frames;
}

final _scrubbers = <(RegExp, String Function(Match))>[
  (RegExp(r'eyJ[\w-]{6,}\.[\w-]{6,}\.[\w-]{6,}'), (_) => '<jwt>'),
  (RegExp(r'[\w.%+-]+@[\w-]+(?:\.[\w-]+)+'), (_) => '<email>'),
  (RegExp(r'\b(Bearer)\s+[\w.~+/=-]+', caseSensitive: false), (m) => '${m[1]} <redacted>'),
  (
    RegExp(
      r'((?:access_token|refresh_token|token|apikey|api_key|password|secret|code)=)[^&\s"]+',
      caseSensitive: false,
    ),
    (m) => '${m[1]}<redacted>',
  ),
  // Word boundaries keep hex addresses in obfuscated stacks intact.
  (RegExp(r'(?<![\w+])(?:\+?88)?01[3-9]\d{8}(?!\w)'), (_) => '<phone>'),
];

/// Masks credentials and contact details that may appear in error text.
String scrubSensitive(String text) {
  var out = text;
  for (final (pattern, replace) in _scrubbers) {
    out = out.replaceAllMapped(pattern, replace);
  }
  return out;
}

/// Trims to [max] UTF-16 units without splitting a surrogate pair, and drops
/// NUL characters (Postgres rejects them in JSON).
String? clip(String? text, int max) {
  if (text == null) return null;
  final clean = text.replaceAll('\u0000', '');
  if (clean.length <= max) return clean;
  final cut = (clean.codeUnitAt(max - 1) & 0xFC00) == 0xD800 ? max - 1 : max;
  return clean.substring(0, cut);
}
