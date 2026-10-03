import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:prostuti/features/exam/application/exam_failure_messages.dart';
import 'package:prostuti/features/question_bank/application/offline_packs.dart';
import 'package:prostuti/features/question_bank/data/offline_pack_store.dart';

/// "120 KB" / "1.4 MB" (Bangla digits in Bangla UI).
String formatBytes(int bytes, {required bool bangla}) {
  if (bytes < 1024) return Fmt.digits('$bytes B', bangla: bangla);
  final kb = bytes / 1024;
  if (kb < 1024) return Fmt.digits('${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB', bangla: bangla);
  return Fmt.digits('${(kb / 1024).toStringAsFixed(1)} MB', bangla: bangla);
}

Future<void> downloadPack(BuildContext context, WidgetRef ref, Subject subject) async {
  final l = context.l10n;
  try {
    await ref.read(offlinePacksProvider.notifier).download(subject.id);
    if (context.mounted) showInfoSnack(context, l.questionBankOfflineDone(subject.name(context)));
  } on NetworkFailure {
    if (context.mounted) showInfoSnack(context, l.offlineUnavailable);
  } on ConflictFailure {
    // Already downloading.
  } on Object catch (e) {
    if (context.mounted) showExamError(context, e);
  }
}

/// Compact download control for subject rows: download → progress →
/// "available offline" (tap for details / update / remove).
class OfflinePackButton extends ConsumerWidget {
  const OfflinePackButton({required this.subject, super.key});

  final Subject subject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final info = ref.watch(offlinePacksProvider.select((s) => s.packs[subject.id]));
    final progress = ref.watch(offlinePacksProvider.select((s) => s.downloading[subject.id]));
    if (progress != null) {
      return Tooltip(
        message: l.questionBankOfflineDownloading(context.n(progress)),
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Center(child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4))),
        ),
      );
    }
    if (info != null) {
      return IconButton(
        tooltip: l.questionBankOfflineReady,
        icon: const Icon(Icons.offline_pin_rounded, color: AppColors.success),
        onPressed: () => unawaited(showOfflinePackSheet(context, subject)),
      );
    }
    return IconButton(
      tooltip: l.questionBankOfflineDownload,
      icon: const Icon(Icons.download_for_offline_outlined),
      onPressed: () => unawaited(downloadPack(context, ref, subject)),
    );
  }
}

/// Details of a downloaded pack with update / remove.
Future<void> showOfflinePackSheet(BuildContext context, Subject subject) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (_) => _PackSheet(subject: subject),
  );
}

class _PackSheet extends ConsumerWidget {
  const _PackSheet({required this.subject});
  final Subject subject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final info = ref.watch(offlinePacksProvider.select((s) => s.packs[subject.id]));
    final progress = ref.watch(offlinePacksProvider.select((s) => s.downloading[subject.id]));
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(subject.iconData, color: subject.color),
              Gap.w8,
              Expanded(child: Text(subject.name(context), style: Theme.of(context).textTheme.titleMedium)),
            ],
          ),
          Gap.h12,
          OfflinePackSummary(info: info, progress: progress),
          Gap.h16,
          if (info != null) ...[
            OutlinedButton.icon(
              onPressed: progress != null ? null : () => unawaited(downloadPack(context, ref, subject)),
              icon: const Icon(Icons.sync_rounded),
              label: Text(l.questionBankOfflineUpdate),
            ),
            Gap.h8,
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              onPressed: progress != null
                  ? null
                  : () async {
                      await ref.read(offlinePacksProvider.notifier).remove(subject.id);
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      showInfoSnack(context, l.questionBankOfflineRemoved);
                    },
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text(l.questionBankOfflineRemove),
            ),
          ] else
            FilledButton.icon(
              onPressed: progress != null ? null : () => unawaited(downloadPack(context, ref, subject)),
              icon: const Icon(Icons.download_rounded),
              label: Text(l.questionBankOfflineDownload),
            ),
        ],
      ),
    );
  }
}

/// One-line status: downloading N… / N questions · size · date.
class OfflinePackSummary extends StatelessWidget {
  const OfflinePackSummary({required this.info, required this.progress, super.key});

  final OfflinePackInfo? info;
  final int? progress;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final bangla = context.isBn;
    if (progress != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.questionBankOfflineDownloading(context.n(progress!)), style: theme.textTheme.bodyMedium),
          Gap.h8,
          const LinearProgressIndicator(),
        ],
      );
    }
    final i = info;
    if (i == null) {
      return Text(
        l.questionBankOfflineBody,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }
    return Row(
      children: [
        const Icon(Icons.offline_pin_rounded, color: AppColors.success, size: 20),
        Gap.w8,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.questionBankOfflineReady, style: theme.textTheme.titleSmall),
              Text(
                l.questionBankOfflineInfo(
                  context.n(i.count),
                  formatBytes(i.bytes, bangla: bangla),
                  Fmt.date(i.downloadedAt, bangla: bangla),
                ),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Card for the subject screen: explains offline practice and manages the
/// pack inline.
class OfflinePackCard extends ConsumerWidget {
  const OfflinePackCard({required this.subject, super.key});

  final Subject subject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final info = ref.watch(offlinePacksProvider.select((s) => s.packs[subject.id]));
    final progress = ref.watch(offlinePacksProvider.select((s) => s.downloading[subject.id]));
    return Card(
      child: Padding(
        padding: Gap.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_download_outlined, color: Theme.of(context).colorScheme.primary),
                Gap.w8,
                Expanded(child: Text(l.questionBankOfflineTitle, style: Theme.of(context).textTheme.titleSmall)),
                if (info != null && progress == null)
                  IconButton(
                    tooltip: l.questionBankOfflineRemove,
                    icon: const Icon(Icons.more_horiz_rounded),
                    onPressed: () => unawaited(showOfflinePackSheet(context, subject)),
                  ),
              ],
            ),
            Gap.h8,
            OfflinePackSummary(info: info, progress: progress),
            if (info == null && progress == null) ...[
              Gap.h12,
              FilledButton.tonalIcon(
                onPressed: () => unawaited(downloadPack(context, ref, subject)),
                icon: const Icon(Icons.download_rounded),
                label: Text(l.questionBankOfflineDownload),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
