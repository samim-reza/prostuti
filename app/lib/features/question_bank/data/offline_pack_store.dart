import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:prostuti/core/network/rpc.dart';
import 'package:prostuti/core/utils/json.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';

/// Key/value storage for offline packs (a dedicated Hive box in the app,
/// an in-memory map in tests).
abstract class PackStorage {
  String? read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class HivePackStorage implements PackStorage {
  HivePackStorage._(this._box);

  static const boxName = 'prostuti_offline_packs_v1';
  final Box<String> _box;

  static Future<HivePackStorage> open() async => HivePackStorage._(await Hive.openBox<String>(boxName));

  /// RAM-only box (tests).
  static Future<HivePackStorage> inMemory() async => HivePackStorage._(
    await Hive.openBox<String>('${boxName}_mem_${DateTime.now().microsecondsSinceEpoch}', bytes: Uint8List(0)),
  );

  @override
  String? read(String key) => _box.get(key);

  @override
  Future<void> write(String key, String value) => _box.put(key, value);

  @override
  Future<void> delete(String key) => _box.delete(key);
}

class MemoryPackStorage implements PackStorage {
  final _map = <String, String>{};

  @override
  String? read(String key) => _map[key];

  @override
  Future<void> write(String key, String value) async => _map[key] = value;

  @override
  Future<void> delete(String key) async => _map.remove(key);
}

/// Summary of a downloaded subject pack (kept in a small index so listing
/// packs never decodes the question payloads).
@immutable
class OfflinePackInfo {
  const OfflinePackInfo({
    required this.subjectId,
    required this.count,
    required this.bytes,
    required this.downloadedAt,
    this.topicIds = const {},
  });

  factory OfflinePackInfo.fromJson(Map<String, dynamic> j) => OfflinePackInfo(
    subjectId: j.integer('subject_id'),
    count: j.integer('count'),
    bytes: j.integer('bytes'),
    downloadedAt: j.dateOr('downloaded_at', DateTime.now()),
    topicIds: (j['topic_ids'] as List?)?.whereType<num>().map((e) => e.toInt()).toSet() ?? const {},
  );

  final int subjectId;
  final int count;
  final int bytes;
  final DateTime downloadedAt;

  /// Topics covered — lets topic practice find its pack without decoding.
  final Set<int> topicIds;

  Map<String, dynamic> toJson() => {
    'subject_id': subjectId,
    'count': count,
    'bytes': bytes,
    'downloaded_at': downloadedAt.toIso8601String(),
    'topic_ids': topicIds.toList(),
  };
}

/// One answer given in pack mode, waiting to be uploaded via
/// `sync_practice_attempts` (idempotent by [clientId]).
@immutable
class PracticeAttempt {
  const PracticeAttempt({
    required this.clientId,
    required this.questionId,
    required this.selectedIndex,
    required this.answeredAt,
  });

  factory PracticeAttempt.fromJson(Map<String, dynamic> j) => PracticeAttempt(
    clientId: j.str('client_id'),
    questionId: j.integer('question_id'),
    selectedIndex: j.integer('selected_index'),
    answeredAt: j.dateOr('answered_at', DateTime.now()),
  );

  final String clientId;
  final int questionId;
  final int selectedIndex;
  final DateTime answeredAt;

  Map<String, dynamic> toJson() => {
    'client_id': clientId,
    'question_id': questionId,
    'selected_index': selectedIndex,
    'answered_at': answeredAt.toUtc().toIso8601String(),
  };
}

/// Per-user offline question packs (questions **with** answers and
/// explanations, from `get_offline_pack`), the local "seen" set and the
/// buffer of answers not yet handed to the sync queue.
class OfflinePackStore {
  OfflinePackStore(this._storage, this._userId);

  final PackStorage _storage;
  final String _userId;
  final _decoded = <int, List<Question>>{};

  String get _indexKey => 'index:$_userId';
  String _packKey(int subjectId) => 'pack:$_userId:$subjectId';
  String get _seenKey => 'seen:$_userId';
  String get _bufferKey => 'buffer:$_userId';

  Map<int, OfflinePackInfo> index() {
    final raw = _storage.read(_indexKey);
    if (raw == null) return {};
    try {
      final infos = (jsonDecode(raw) as List).whereType<Map<dynamic, dynamic>>().map(
        (e) => OfflinePackInfo.fromJson(Map<String, dynamic>.from(e)),
      );
      return {for (final info in infos) info.subjectId: info};
    } on Object {
      return {};
    }
  }

  Future<void> _writeIndex(Map<int, OfflinePackInfo> index) =>
      _storage.write(_indexKey, jsonEncode(index.values.map((e) => e.toJson()).toList()));

  /// Replaces the pack of [subjectId] with [questions].
  Future<OfflinePackInfo> save(int subjectId, List<Question> questions) async {
    final payload = jsonEncode(questions.map((q) => q.toJson()).toList());
    await _storage.write(_packKey(subjectId), payload);
    _decoded[subjectId] = List.unmodifiable(questions);
    final info = OfflinePackInfo(
      subjectId: subjectId,
      count: questions.length,
      bytes: utf8.encode(payload).length,
      downloadedAt: DateTime.now(),
      topicIds: questions.map((q) => q.topicId).whereType<int>().toSet(),
    );
    await _writeIndex({...index(), subjectId: info});
    return info;
  }

  Future<void> remove(int subjectId) async {
    _decoded.remove(subjectId);
    await _storage.delete(_packKey(subjectId));
    await _writeIndex(index()..remove(subjectId));
  }

  /// Decoded questions (large payloads are parsed off the UI thread).
  Future<List<Question>?> load(int subjectId) async {
    final hot = _decoded[subjectId];
    if (hot != null) return hot;
    final raw = _storage.read(_packKey(subjectId));
    if (raw == null) return null;
    try {
      final json = await decodeJsonInBackground(raw);
      final list = (json! as List)
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => Question.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
      return _decoded[subjectId] = list;
    } on Object {
      return null;
    }
  }

  Set<int> seen() {
    final raw = _storage.read(_seenKey);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as List).whereType<num>().map((e) => e.toInt()).toSet();
    } on Object {
      return {};
    }
  }

  Future<void> markSeen(Iterable<int> ids) => _storage.write(_seenKey, jsonEncode({...seen(), ...ids}.toList()));

  List<PracticeAttempt> buffered() {
    final raw = _storage.read(_bufferKey);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => PracticeAttempt.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on Object {
      return const [];
    }
  }

  /// Appends an attempt; returns the buffer size.
  Future<int> buffer(PracticeAttempt attempt) async {
    final next = [...buffered(), attempt];
    await _storage.write(_bufferKey, jsonEncode(next.map((e) => e.toJson()).toList()));
    return next.length;
  }

  /// Removes and returns everything buffered.
  Future<List<PracticeAttempt>> drain() async {
    final all = buffered();
    if (all.isNotEmpty) await _storage.delete(_bufferKey);
    return all;
  }

  /// Puts attempts back (e.g. the sync call was rate-limited).
  Future<void> restore(List<PracticeAttempt> attempts) async {
    if (attempts.isEmpty) return;
    final next = [...attempts, ...buffered()];
    await _storage.write(_bufferKey, jsonEncode(next.map((e) => e.toJson()).toList()));
  }
}
