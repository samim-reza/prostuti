import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Space-efficient probabilistic set: "definitely not present" or "probably
/// present". Used to skip work for ids we have certainly never seen
/// (e.g. de-duplicating realtime events and feed pages) without keeping
/// every id in memory.
///
/// Uses Kirsch–Mitzenmacher double hashing (h1 + i·h2) over two 32-bit FNV-1a
/// variants, which gives k independent-enough hash positions in O(k).
class BloomFilter {
  /// Sizes the filter for [expectedItems] at the target false-positive rate.
  factory BloomFilter({required int expectedItems, double falsePositiveRate = 0.01}) {
    assert(expectedItems > 0 && falsePositiveRate > 0 && falsePositiveRate < 1, 'invalid sizing');
    final m = (-expectedItems * math.log(falsePositiveRate) / (math.ln2 * math.ln2)).ceil();
    final k = math.max(1, (m / expectedItems * math.ln2).round());
    return BloomFilter._(Uint8List((m + 7) >> 3), m, k);
  }

  BloomFilter._(this._bits, this.bitCount, this.hashCount);

  final Uint8List _bits;
  final int bitCount;
  final int hashCount;
  int _inserted = 0;

  int get approximateCount => _inserted;

  void add(String value) {
    final (h1, h2) = _hashes(value);
    for (var i = 0; i < hashCount; i++) {
      final bit = (h1 + i * h2) % bitCount;
      _bits[bit >> 3] |= 1 << (bit & 7);
    }
    _inserted++;
  }

  bool mightContain(String value) {
    final (h1, h2) = _hashes(value);
    for (var i = 0; i < hashCount; i++) {
      final bit = (h1 + i * h2) % bitCount;
      if (_bits[bit >> 3] & (1 << (bit & 7)) == 0) return false;
    }
    return true;
  }

  /// Adds [value] and returns true if it was (probably) already present.
  bool testAndAdd(String value) {
    final present = mightContain(value);
    if (!present) add(value);
    return present;
  }

  void clear() {
    _bits.fillRange(0, _bits.length, 0);
    _inserted = 0;
  }

  static (int, int) _hashes(String value) {
    final bytes = utf8.encode(value);
    var h1 = 0x811c9dc5;
    var h2 = 0x01000193 ^ 0x5bd1e995;
    for (final b in bytes) {
      h1 = ((h1 ^ b) * 0x01000193) & 0xFFFFFFFF;
      h2 = ((h2 ^ b) * 0x5bd1e995) & 0xFFFFFFFF;
    }
    // h2 must be odd so the probe sequence covers the whole table.
    return (h1, h2 | 1);
  }
}
