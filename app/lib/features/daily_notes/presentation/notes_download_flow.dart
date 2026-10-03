import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:prostuti/core/config/remote_config.dart';
import 'package:prostuti/core/entitlements/feature_access.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/services/ads_service.dart';
import 'package:prostuti/core/services/pdf_export_service.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/daily_notes/application/current_affairs_failures.dart';
import 'package:prostuti/features/daily_notes/application/today_notes_controller.dart';
import 'package:prostuti/features/daily_notes/data/daily_note.dart';
import 'package:prostuti/features/daily_notes/data/daily_notes_repository.dart';
import 'package:prostuti/features/daily_notes/presentation/screens/downloaded_notes_screen.dart';
import 'package:prostuti/features/daily_notes/presentation/widgets/note_category_style.dart';
import 'package:prostuti/features/daily_notes/presentation/widgets/notes_print_blocks.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';

/// `prostuti-notes-2026-10-04.pdf`
String notesPdfFileName(String isoDate) => 'prostuti-notes-$isoDate.pdf';

/// "রবিবার, ৪ অক্টোবর ২০২৬" / "Sunday, 4 October 2026" for a UTC-flagged
/// calendar date.
String notesLongDate(DateTime date, {required bool bangla}) =>
    DateFormat('EEEE, d MMMM y', bangla ? 'bn' : 'en').format(date);

/// Starts the rewarded ad preload for users who will need it.
Future<void> preloadNotesAd(WidgetRef ref) async {
  try {
    final access = await ref.read(featureAccessProvider.future);
    if (access[Features.adFree] ?? false) return;
  } on Object {
    // Unknown entitlements: preloading is harmless.
  }
  final config = await ref.read(remoteConfigProvider.future);
  if (!config.rewardedAdsEnabled) return;
  AdsService.instance.preload(remoteAndroid: config.androidRewardedUnit, remoteIos: config.iosRewardedUnit);
}

/// "Download today's notes as PDF":
///  1. first download of the day (needs the network): ad-free add-on →
///     `claim_note_download('addon')`; otherwise explain → rewarded ad →
///     only when earned `claim('ad')`. Repeat downloads skip this step;
///  2. render print-designed blocks to an A4 PDF with an `@username`
///     watermark, save it under "downloaded notes" and open the share sheet.
///
/// [onBusy] shows/hides the progress overlay (null hides it).
Future<void> downloadTodayNotesPdf({
  required BuildContext context,
  required WidgetRef ref,
  required TodayNotes today,
  required ValueChanged<String?> onBusy,
}) async {
  final l = context.l10n;
  final bangla = context.isBn;
  if (today.notes.isEmpty) return;

  final repo = ref.read(dailyNotesRepositoryProvider);
  final adFree = ref.read(hasFeatureProvider(Features.adFree));

  // Today's download is already claimed → the PDF is rendered on device,
  // so a repeat download works offline and needs no second ad.
  if (!today.downloaded) {
    if (!ConnectivityService.instance.isOnline) {
      showInfoSnack(context, l.offlineUnavailable);
      return;
    }
    try {
      if (adFree) {
        await repo.claimDownload(DownloadMethod.addon);
      } else {
        final accepted = await _explainAd(context);
        if (!accepted || !context.mounted) return;
        final config = await ref.read(remoteConfigProvider.future);
        if (config.rewardedAdsEnabled) {
          onBusy(l.dailyNotesLoadingAd);
          final earned = await AdsService.instance.showRewarded(
            remoteAndroid: config.androidRewardedUnit,
            remoteIos: config.iosRewardedUnit,
          );
          onBusy(null);
          if (!earned) {
            if (context.mounted) {
              showInfoSnack(
                context,
                ConnectivityService.instance.isOnline ? l.dailyNotesAdNotCompleted : l.offlineUnavailable,
              );
            }
            return;
          }
        }
        await repo.claimDownload(DownloadMethod.ad);
      }
    } on Object catch (e) {
      onBusy(null);
      if (!context.mounted) return;
      final failure = AppFailure.from(e);
      if (failure is FeatureLockedFailure) {
        showLockedSheet(context);
      } else if (failure is NetworkFailure) {
        showInfoSnack(context, l.offlineUnavailable);
      } else {
        showInfoSnack(context, currentAffairsErrorText(context, e));
      }
      return;
    }
  }
  ref.read(todayNotesProvider.notifier).markDownloaded();
  if (!context.mounted) return;

  onBusy(l.dailyNotesGeneratingPdf);
  try {
    final username = await _username(ref);
    if (!context.mounted) return;
    final strings = NotesPrintStrings(
      brand: l.dailyNotesPdfBrand,
      tagline: l.dailyNotesPdfTagline,
      dateLabel: today.date == null ? today.noteDate : notesLongDate(today.date!, bangla: bangla),
      countLabel: l.dailyNotesNoteCount(Fmt.digits(today.notes.length, bangla: bangla)),
      keyFacts: l.dailyNotesKeyFacts,
      probableQuestions: l.dailyNotesPdfProbableQuestions,
      answer: l.dailyNotesAnswer,
      sources: l.dailyNotesSources,
      footer: l.dailyNotesPdfFooter,
      downloadedBy: username == null ? '' : l.dailyNotesPdfDownloadedBy(username),
      categoryLabel: (c) => noteCategoryLabel(l, c),
      importanceLabel: (level) => noteImportanceLabel(l, level),
      bangla: bangla,
    );
    // Let the overlay paint before the (synchronous) off-screen layouts.
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) return;
    final bytes = await PdfExportService.instance.buildPdf(
      context: context,
      blocks: [
        NotesPrintHeader(strings: strings),
        for (var i = 0; i < today.notes.length; i++)
          NotePrintBlock(note: today.notes[i], index: i + 1, strings: strings),
        NotesPrintFooter(strings: strings),
      ],
      watermark: username == null ? null : '@$username',
    );
    final fileName = notesPdfFileName(today.noteDate);
    if (!kIsWeb) await PdfExportService.instance.save(bytes, fileName);
    onBusy(null);
    if (context.mounted && !kIsWeb) _showSavedSnack(context);
    await Printing.sharePdf(bytes: bytes, filename: fileName);
  } on Object catch (e) {
    debugPrint('notes pdf failed: $e');
    onBusy(null);
    if (context.mounted) showInfoSnack(context, l.dailyNotesPdfFailed);
  }
}

Future<String?> _username(WidgetRef ref) async {
  try {
    final profile = ref.read(currentProfileProvider).value ?? await ref.read(currentProfileProvider.future);
    final name = profile?.username.trim() ?? '';
    return name.isEmpty ? null : name;
  } on Object {
    return null;
  }
}

void _showSavedSnack(BuildContext context) {
  final l = context.l10n;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(l.dailyNotesPdfSaved),
        // Snack bars with an action stay until dismissed by default; this
        // one is a hint, so let it time out.
        persist: false,
        action: SnackBarAction(
          label: l.dailyNotesView,
          onPressed: () {
            if (!context.mounted) return;
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DownloadedNotesScreen()));
          },
        ),
      ),
    );
}

/// "Watch a short ad to download today's notes as a PDF".
Future<bool> _explainAd(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final l = ctx.l10n;
      final theme = Theme.of(ctx);
      return AlertDialog(
        icon: Icon(Icons.picture_as_pdf_rounded, color: theme.colorScheme.primary, size: 32),
        title: Text(l.dailyNotesAdDialogTitle, textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l.dailyNotesAdDialogBody,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            Gap.h12,
            TextButton.icon(
              onPressed: () {
                final router = GoRouter.of(ctx);
                Navigator.pop(ctx, false);
                unawaited(router.push(Routes.addons));
              },
              icon: const Icon(Icons.workspace_premium_rounded, size: 18),
              label: Text(l.dailyNotesAdDialogAdFree),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.ondemand_video_rounded, size: 20),
            label: Text(l.dailyNotesAdDialogWatch),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
