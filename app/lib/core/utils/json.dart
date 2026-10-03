/// Null-safe readers for loosely typed JSON coming from Postgres RPCs.
/// Keeps model `fromJson` constructors short and crash-free.
extension JsonRead on Map<String, dynamic> {
  String str(String key, [String fallback = '']) => this[key]?.toString() ?? fallback;
  String? strOrNull(String key) => this[key]?.toString();
  int integer(String key, [int fallback = 0]) => switch (this[key]) {
    final int v => v,
    final num v => v.toInt(),
    final String v => int.tryParse(v) ?? fallback,
    _ => fallback,
  };
  int? intOrNull(String key) => switch (this[key]) {
    final int v => v,
    final num v => v.toInt(),
    final String v => int.tryParse(v),
    _ => null,
  };
  double dbl(String key, [double fallback = 0]) => switch (this[key]) {
    final num v => v.toDouble(),
    final String v => double.tryParse(v) ?? fallback,
    _ => fallback,
  };
  double? dblOrNull(String key) => switch (this[key]) {
    final num v => v.toDouble(),
    final String v => double.tryParse(v),
    _ => null,
  };
  bool boolean(String key, [bool fallback = false]) => switch (this[key]) {
    final bool v => v,
    _ => fallback,
  };
  DateTime? date(String key) => this[key] == null ? null : DateTime.tryParse(this[key].toString());
  DateTime dateOr(String key, DateTime fallback) => date(key) ?? fallback;
  List<T> list<T>(String key, T Function(Map<String, dynamic>) map) =>
      (this[key] as List?)?.whereType<Map<dynamic, dynamic>>().map((e) => map(Map<String, dynamic>.from(e))).toList() ??
      <T>[];
  List<String> strings(String key) => (this[key] as List?)?.map((e) => e.toString()).toList() ?? const [];
  Map<String, dynamic> obj(String key) =>
      this[key] is Map ? Map<String, dynamic>.from(this[key] as Map) : <String, dynamic>{};
  Map<String, dynamic>? objOrNull(String key) => this[key] is Map ? Map<String, dynamic>.from(this[key] as Map) : null;
}
