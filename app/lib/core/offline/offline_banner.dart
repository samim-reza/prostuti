import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/offline/offline_queue.dart';

/// App-wide strip shown while offline (and while queued changes are syncing).
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService.instance.listenable,
      builder: (context, online, _) => ValueListenableBuilder<int>(
        valueListenable: OfflineQueue.instance.pendingCount,
        builder: (context, pending, _) {
          final show = !online || pending > 0;
          final l = context.l10n;
          final text = !online
              ? (pending > 0 ? '${l.offlineBanner} · ${l.offlinePending(context.n(pending))}' : l.offlineBanner)
              : l.offlineSyncing(context.n(pending));
          return Column(
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                child: show
                    ? Material(
                        color: online ? const Color(0xFF2F6FDE) : const Color(0xFF3A4440),
                        child: SafeArea(
                          bottom: false,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: Row(
                              children: [
                                Icon(
                                  online ? Icons.sync_rounded : Icons.cloud_off_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    text,
                                    style: const TextStyle(color: Colors.white, fontSize: 12.5),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              Expanded(
                child: MediaQuery.removePadding(context: context, removeTop: show, child: child),
              ),
            ],
          );
        },
      ),
    );
  }
}
