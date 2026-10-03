import 'dart:async';

import 'package:prostuti/core/offline/connectivity.dart';

/// Opens a Realtime subscription only while the device is online.
///
/// * [connect] runs immediately when online, otherwise on the first
///   offline → online transition (no doomed socket attempts while offline);
/// * [onReconnect] runs on every offline → online transition, so callers can
///   refetch whatever changed while they were not listening.
///
/// Returns a canceller; call it from `onDispose`.
void Function() connectWhenOnline({
  required void Function() connect,
  void Function()? onReconnect,
  bool? isOnline,
  Stream<bool>? changes,
}) {
  var connected = false;
  void ensureConnected() {
    if (connected) return;
    connected = true;
    connect();
  }

  if (isOnline ?? ConnectivityService.instance.isOnline) ensureConnected();
  final sub = (changes ?? ConnectivityService.instance.changes).listen((online) {
    if (!online) return;
    ensureConnected();
    onReconnect?.call();
  });
  return () => unawaited(sub.cancel());
}
