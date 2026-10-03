import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/features/feed/application/post_events.dart';
import 'package:prostuti/features/feed/data/feed_repository.dart';
import 'package:prostuti/features/feed/data/post.dart';

void main() {
  group('sniffImageType', () {
    test('detects JPEG and PNG, defaults to WebP', () {
      expect(sniffImageType(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0])).mime, 'image/jpeg');
      expect(sniffImageType(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D])).extension, 'png');
      final webp = Uint8List.fromList('RIFF\x00\x00\x00\x00WEBPVP8 '.codeUnits);
      expect(sniffImageType(webp).mime, 'image/webp');
      expect(sniffImageType(Uint8List(0)).extension, 'webp');
    });
  });

  group('storagePathFromPublicUrl', () {
    test('extracts the object path of a public URL', () {
      expect(
        storagePathFromPublicUrl(
          'https://abc.supabase.co/storage/v1/object/public/post-media/u1/9f%20x.webp?t=1',
          'post-media',
        ),
        'u1/9f x.webp',
      );
    });

    test('returns null for other buckets or URLs', () {
      expect(
        storagePathFromPublicUrl('https://abc.supabase.co/storage/v1/object/public/avatars/u1/a.webp', 'post-media'),
        isNull,
      );
      expect(storagePathFromPublicUrl('https://example.com/a.webp', 'post-media'), isNull);
    });
  });

  group('keysetPage', () {
    final now = DateTime.utc(2026, 10, 4);
    Keyset cursorOf(int i) => Keyset(now.subtract(Duration(minutes: i)), 'id$i');

    test('a full page continues from its last item', () {
      final page = keysetPage(List.generate(20, (i) => i), 20, cursorOf);
      expect(page.nextCursor, cursorOf(19));
    });

    test('a short or empty page ends the list', () {
      expect(keysetPage(List.generate(7, (i) => i), 20, cursorOf).nextCursor, isNull);
      expect(keysetPage(<int>[], 20, cursorOf).nextCursor, isNull);
    });

    test('Keyset serializes created_at as UTC ISO-8601 with microseconds', () {
      final k = Keyset(DateTime.parse('2026-10-03T21:11:53.338105+00:00'), 'x');
      expect(k.createdAtIso, '2026-10-03T21:11:53.338105Z');
    });
  });
}
