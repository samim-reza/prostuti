import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/services/pdf_export_service.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/daily_notes/application/downloaded_files.dart';
import 'package:share_plus/share_plus.dart';

/// A saved PDF with the metadata shown in the list.
class _SavedPdf {
  const _SavedPdf({required this.file, required this.name, required this.size, required this.modified, this.date});

  final File file;
  final String name;
  final int size;
  final DateTime modified;
  final DateTime? date;
}

/// "ডাউনলোড করা নোট": PDFs saved on this phone — open, share or delete,
/// fully offline.
class DownloadedNotesScreen extends StatefulWidget {
  const DownloadedNotesScreen({super.key});

  @override
  State<DownloadedNotesScreen> createState() => _DownloadedNotesScreenState();
}

class _DownloadedNotesScreenState extends State<DownloadedNotesScreen> {
  List<_SavedPdf>? _items;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final files = await PdfExportService.instance.listSaved();
      final items = <_SavedPdf>[];
      for (final f in files) {
        final stat = f.statSync();
        items.add(
          _SavedPdf(
            file: f,
            name: fileBaseName(f.path),
            size: stat.size,
            modified: stat.modified,
            date: notesDateFromFileName(f.path),
          ),
        );
      }
      // Newest notes first (by notes date, then by save time).
      items.sort((a, b) {
        final ad = a.date ?? a.modified;
        final bd = b.date ?? b.modified;
        return bd.compareTo(ad);
      });
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _open(_SavedPdf item) async {
    try {
      await Printing.layoutPdf(onLayout: (_) => item.file.readAsBytes(), name: item.name);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _share(_SavedPdf item) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(item.file.path, mimeType: 'application/pdf', name: item.name)],
          title: item.name,
        ),
      );
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _delete(_SavedPdf item) async {
    final l = context.l10n;
    final ok = await confirmDialog(
      context,
      title: l.dailyNotesDeleteTitle,
      message: l.dailyNotesDeleteBody,
      confirmLabel: l.delete,
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      if (item.file.existsSync()) await item.file.delete();
      setState(() => _items = [...?_items]..remove(item));
      if (mounted) showInfoSnack(context, l.dailyNotesDeleted);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final items = _items;
    Widget body;
    if (_error != null && items == null) {
      body = ErrorView(error: _error!, onRetry: _load);
    } else if (items == null) {
      body = const SkeletonList(itemCount: 4);
    } else if (items.isEmpty) {
      body = LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: c.maxHeight,
            child: EmptyView(
              icon: Icons.download_for_offline_outlined,
              title: l.dailyNotesDownloadsEmptyTitle,
              message: l.dailyNotesDownloadsEmptyBody,
            ),
          ),
        ),
      );
    } else {
      body = ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Gap.lg),
        itemCount: items.length,
        separatorBuilder: (_, _) => Gap.h12,
        itemBuilder: (context, i) => _SavedPdfTile(
          item: items[i],
          onOpen: () => _open(items[i]),
          onShare: () => _share(items[i]),
          onDelete: () => _delete(items[i]),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.dailyNotesDownloadedNotes)),
      body: RefreshIndicator(onRefresh: _load, child: body),
    );
  }
}

class _SavedPdfTile extends StatelessWidget {
  const _SavedPdfTile({required this.item, required this.onOpen, required this.onShare, required this.onDelete});

  final _SavedPdf item;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bangla = context.isBn;
    final title = item.date == null ? item.name : l.dailyNotesDownloadsFileTitle(Fmt.date(item.date!, bangla: bangla));
    final size = fileSizeParts(item.size, bangla: bangla);
    final sizeLabel = size.megabytes ? l.dailyNotesSizeMb(size.value) : l.dailyNotesSizeKb(size.value);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Semantics(
          button: true,
          hint: l.dailyNotesOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.xs, Gap.md),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: scheme.error.withValues(alpha: 0.1),
                    borderRadius: const BorderRadius.all(Radii.md),
                  ),
                  child: Icon(Icons.picture_as_pdf_rounded, color: scheme.error),
                ),
                Gap.w12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                      Gap.h4,
                      Text(
                        '$sizeLabel · ${Fmt.timeAgo(item.modified, bangla: bangla)}',
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(onPressed: onShare, tooltip: l.share, icon: const Icon(Icons.share_rounded)),
                IconButton(onPressed: onDelete, tooltip: l.delete, icon: const Icon(Icons.delete_outline_rounded)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
