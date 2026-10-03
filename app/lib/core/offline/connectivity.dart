import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks whether the device has a network connection.
///
/// `connectivity_plus` only reports the *interface* (Wi-Fi / mobile), so a
/// failed request also flips the state to offline via [reportFailure]; the
/// next successful request (or interface change) flips it back. Repositories
/// consult [isOnline] to skip doomed network calls and serve cache instantly.
class ConnectivityService {
  ConnectivityService._();
  static final instance = ConnectivityService._();

  final _online = ValueNotifier<bool>(true);
  bool _hasInterface = true;
  final _controller = StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _sub;

  ValueListenable<bool> get listenable => _online;
  bool get isOnline => _online.value;

  /// Wi-Fi / mobile data is up (requests *may* work even if [isOnline] is
  /// false after a failure — callers use this to attempt background refreshes).
  bool get hasInterface => _hasInterface;
  Stream<bool> get changes => _controller.stream;

  Future<void> init() async {
    if (_sub != null) return;
    try {
      _onInterface(await Connectivity().checkConnectivity());
      _sub = Connectivity().onConnectivityChanged.listen(_onInterface);
    } on Object {
      // Plugin unavailable (tests/desktop): assume online.
    }
  }

  void _onInterface(List<ConnectivityResult> r) {
    _hasInterface = r.any((e) => e != ConnectivityResult.none);
    _set(_hasInterface);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// A request failed with a network error.
  void reportFailure() => _set(false);

  /// A request succeeded.
  void reportSuccess() => _set(true);

  void _set(bool value) {
    if (_online.value == value) return;
    _online.value = value;
    _controller.add(value);
  }
}

/// `true` while online. Rebuilds widgets when connectivity changes.
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final service = ConnectivityService.instance;
  yield service.isOnline;
  yield* service.changes;
});
