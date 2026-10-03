import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/offline/offline_queue.dart';
import 'package:prostuti/features/question_bank/data/offline_pack_store.dart';
import 'package:prostuti/features/question_bank/data/question_bank_repository.dart';
import 'package:uuid/uuid.dart';

@immutable
class OfflinePacksState {
  const OfflinePacksState({this.packs = const {}, this.downloading = const {}});

  /// subject id → downloaded pack summary.
  final Map<int, OfflinePackInfo> packs;

  /// subject id → questions fetched so far (download in progress).
  final Map<int, int> downloading;

  OfflinePacksState copyWith({Map<int, OfflinePackInfo>? packs, Map<int, int>? downloading}) =>
      OfflinePacksState(packs: packs ?? this.packs, downloading: downloading ?? this.downloading);
}

/// Downloaded subject packs: list, download (paged `get_offline_pack`),
/// update and remove.
class OfflinePacksNotifier extends Notifier<OfflinePacksState> {
  @override
  OfflinePacksState build() {
    final store = ref.watch(offlinePackStoreProvider).value;
    return OfflinePacksState(packs: store?.index() ?? const {});
  }

  /// Downloads (or refreshes) the pack of [subjectId]. Needs the network.
  Future<OfflinePackInfo> download(int subjectId) async {
    if (state.downloading.containsKey(subjectId)) throw const ConflictFailure('download_in_progress');
    if (!ConnectivityService.instance.isOnline) throw const NetworkFailure();
    state = state.copyWith(downloading: {...state.downloading, subjectId: 0});
    try {
      final store = await ref.read(offlinePackStoreProvider.future);
      final questions = await ref
          .read(questionBankRepositoryProvider)
          .downloadOfflinePack(
            subjectId,
            onProgress: (n) {
              if (ref.mounted) state = state.copyWith(downloading: {...state.downloading, subjectId: n});
            },
          );
      final info = await store.save(subjectId, questions);
      if (ref.mounted) {
        state = OfflinePacksState(
          packs: {...state.packs, subjectId: info},
          downloading: {...state.downloading}..remove(subjectId),
        );
      }
      return info;
    } on Object {
      if (ref.mounted) state = state.copyWith(downloading: {...state.downloading}..remove(subjectId));
      rethrow;
    }
  }

  Future<void> remove(int subjectId) async {
    final store = await ref.read(offlinePackStoreProvider.future);
    await store.remove(subjectId);
    if (ref.mounted) state = state.copyWith(packs: {...state.packs}..remove(subjectId));
  }
}

final offlinePacksProvider = NotifierProvider<OfflinePacksNotifier, OfflinePacksState>(OfflinePacksNotifier.new);

/// Hands buffered pack-mode answers to the offline queue in batches.
abstract final class PracticeSync {
  static const batchSize = 20;
  static const _uuid = Uuid();

  static String newClientId() => _uuid.v4();

  /// Drains the buffer of [store] into `practice.sync` queue items of
  /// [batchSize] answers. Rate-limited batches go back into the buffer;
  /// anything else the server rejects is dropped (it would never succeed).
  static Future<void> flush(OfflinePackStore store) async {
    final attempts = await store.drain();
    for (var i = 0; i < attempts.length; i += batchSize) {
      final chunk = attempts.sublist(i, i + batchSize > attempts.length ? attempts.length : i + batchSize);
      try {
        await OfflineQueue.instance.run(QuestionBankRepository.syncOp, {
          'attempts': chunk.map((a) => a.toJson()).toList(),
        }, id: chunk.first.clientId);
      } on RateLimitFailure {
        await store.restore(attempts.sublist(i));
        return;
      } on Object catch (e) {
        debugPrint('practice sync: dropping ${chunk.length} answers: $e');
      }
    }
  }
}
