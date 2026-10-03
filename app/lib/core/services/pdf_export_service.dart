import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds PDFs from Flutter widgets.
///
/// Why images? The `pdf` package cannot shape Bangla conjuncts (যুক্তাক্ষর)
/// correctly, while Flutter's text engine (HarfBuzz) can. So every block is
/// rendered off-screen with Flutter at print resolution and placed on A4
/// pages — the result looks exactly like the app.
class PdfExportService {
  PdfExportService._();
  static final instance = PdfExportService._();

  /// A4 width in PDF points; blocks are laid out at this logical width.
  static const pageWidth = 595.0;
  static const pageHeight = 842.0;
  static const margin = 28.0;

  /// Renders [blocks] (header, notes, footer…) and paginates them greedily:
  /// each block goes on the current page if it fits, otherwise on a new one;
  /// a block taller than a page is scaled down to fit.
  Future<Uint8List> buildPdf({
    required BuildContext context,
    required List<Widget> blocks,
    String? watermark,
    double pixelRatio = 2.5,
  }) async {
    final theme = Theme.of(context);
    const contentWidth = pageWidth - margin * 2;
    final images = <(Uint8List, Size)>[];
    for (final block in blocks) {
      images.add(await _render(block, theme: theme, width: contentWidth, pixelRatio: pixelRatio));
    }

    final doc = pw.Document(title: 'Prostuti', author: 'Prostuti', creator: 'Prostuti app');
    const maxHeight = pageHeight - margin * 2 - 18;
    final pages = <List<(Uint8List, Size)>>[[]];
    var used = 0.0;
    for (final img in images) {
      final h = img.$2.height.clamp(0, maxHeight).toDouble();
      if (used + h > maxHeight && pages.last.isNotEmpty) {
        pages.add([]);
        used = 0;
      }
      pages.last.add(img);
      used += h + 8;
    }

    for (var i = 0; i < pages.length; i++) {
      final pageImages = pages[i];
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(margin),
          build: (_) => pw.Stack(
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  for (final (bytes, size) in pageImages)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 8),
                      child: pw.Image(
                        pw.MemoryImage(bytes),
                        width: contentWidth,
                        height: size.height.clamp(0, maxHeight).toDouble(),
                      ),
                    ),
                  pw.Spacer(),
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text(
                      '${i + 1} / ${pages.length}',
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                    ),
                  ),
                ],
              ),
              if (watermark != null)
                pw.Center(
                  child: pw.Transform.rotate(
                    angle: -0.6,
                    child: pw.Opacity(
                      opacity: 0.06,
                      child: pw.Text(watermark, style: const pw.TextStyle(fontSize: 34)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return doc.save();
  }

  /// Saves under the app's documents folder (works offline; listed in-app as
  /// "downloaded notes"). Returns the file path.
  Future<String> save(Uint8List bytes, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/downloads');
    if (!folder.existsSync()) folder.createSync(recursive: true);
    final file = File('${folder.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<List<File>> listSaved() async {
    if (kIsWeb) return const [];
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/downloads');
    if (!folder.existsSync()) return const [];
    final files = folder.listSync().whereType<File>().where((f) => f.path.endsWith('.pdf')).toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  /// Off-screen render of [widget] at a fixed logical width; height is
  /// whatever the content needs.
  Future<(Uint8List, Size)> _render(
    Widget widget, {
    required ThemeData theme,
    required double width,
    required double pixelRatio,
  }) async {
    final boundary = RenderRepaintBoundary();
    final view = ui.PlatformDispatcher.instance.implicitView ?? ui.PlatformDispatcher.instance.views.first;
    final renderView = RenderView(
      view: view,
      child: RenderPositionedBox(alignment: Alignment.topLeft, child: boundary),
      configuration: ViewConfiguration(
        logicalConstraints: BoxConstraints(minWidth: width, maxWidth: width, maxHeight: 20000),
        devicePixelRatio: pixelRatio,
      ),
    );
    final pipeline = PipelineOwner()..rootNode = renderView;
    renderView.prepareInitialFrame();

    final buildOwner = BuildOwner(focusManager: FocusManager());
    final root = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: MediaQuery(
        data: MediaQueryData(size: Size(width, 20000), devicePixelRatio: pixelRatio),
        child: Theme(
          data: theme,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: DefaultTextStyle(
              style: theme.textTheme.bodyMedium ?? const TextStyle(),
              child: Material(
                color: Colors.white,
                child: SizedBox(width: width, child: widget),
              ),
            ),
          ),
        ),
      ),
    ).attachToRenderTree(buildOwner);

    buildOwner
      ..buildScope(root)
      ..finalizeTree();
    pipeline
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();

    final size = boundary.size;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return (data!.buffer.asUint8List(), size);
  }
}
