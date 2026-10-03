import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:prostuti/core/config/app_constants.dart';

/// Picks images and shrinks them *before* upload: longest side ≤ 1280 px,
/// WebP at ~78% quality. A typical 4 MB phone photo becomes ~150 KB, which
/// saves users' mobile data and keeps storage/egress costs low.
class MediaService {
  MediaService._();
  static final instance = MediaService._();

  final _picker = ImagePicker();

  Future<Uint8List?> pickOne({
    ImageSource source = ImageSource.gallery,
    int maxDimension = AppConstants.imageMaxDimension,
  }) async {
    final file = await _picker.pickImage(source: source, requestFullMetadata: false);
    if (file == null) return null;
    return compress(await file.readAsBytes(), maxDimension: maxDimension);
  }

  Future<List<Uint8List>> pickMany({int limit = AppConstants.maxPostImages}) async {
    final files = await _picker.pickMultiImage(limit: limit, requestFullMetadata: false);
    final out = <Uint8List>[];
    for (final f in files.take(limit)) {
      out.add(await compress(await f.readAsBytes()));
    }
    return out;
  }

  Future<Uint8List> compress(Uint8List bytes, {int maxDimension = AppConstants.imageMaxDimension}) async {
    if (kIsWeb) return bytes; // the web compressor is not available; upload as-is
    try {
      return await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: maxDimension,
        minHeight: maxDimension,
        quality: AppConstants.imageQuality,
        format: CompressFormat.webp,
      );
    } on Object {
      return bytes;
    }
  }
}

final mediaServiceProvider = Provider<MediaService>((ref) => MediaService.instance);
