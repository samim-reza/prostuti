import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/widgets/state_views.dart';

/// For actions that truly need the network (starting an exam, AI calls,
/// re-planning): fails fast with a clear message instead of a spinner that
/// never ends. Returns true when online.
bool ensureOnline(BuildContext context) {
  if (ConnectivityService.instance.isOnline) return true;
  showInfoSnack(context, context.l10n.offlineUnavailable);
  return false;
}
