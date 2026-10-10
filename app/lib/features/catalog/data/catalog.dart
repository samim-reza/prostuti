import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/cache/cached_fetcher.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/network/rpc.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/utils/json.dart';
import 'package:prostuti/features/catalog/data/exam_track.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

export 'package:prostuti/features/catalog/data/exam_track.dart';

@immutable
class Topic {
  const Topic({required this.id, required this.code, required this.nameBn, required this.nameEn, this.mastery});

  factory Topic.fromJson(Map<String, dynamic> j) => Topic(
    id: j.integer('id'),
    code: j.str('code'),
    nameBn: j.str('name_bn'),
    nameEn: j.str('name_en'),
    mastery: j.dblOrNull('mastery'),
  );

  final int id;
  final String code;
  final String nameBn;
  final String nameEn;

  /// 0…1, null when the user has never been assessed on it.
  final double? mastery;

  String name(BuildContext context) => context.isBn ? nameBn : nameEn;

  Map<String, dynamic> toJson() => {'id': id, 'code': code, 'name_bn': nameBn, 'name_en': nameEn, 'mastery': mastery};
}

@immutable
class Subject {
  const Subject({
    required this.id,
    required this.code,
    required this.nameBn,
    required this.nameEn,
    required this.bcsMarks,
    this.trackMarks,
    this.icon,
    this.colorHex,
    this.questionCount = 0,
    this.mastery,
    this.topics = const [],
  });

  factory Subject.fromJson(Map<String, dynamic> j) => Subject(
    id: j.integer('id'),
    code: j.str('code'),
    nameBn: j.str('name_bn'),
    nameEn: j.str('name_en'),
    bcsMarks: j.integer('bcs_marks'),
    trackMarks: j.intOrNull('track_marks'),
    icon: j.strOrNull('icon'),
    colorHex: j.strOrNull('color'),
    questionCount: j.integer('question_count'),
    mastery: j.dblOrNull('mastery'),
    topics: j.list('topics', Topic.fromJson),
  );

  final int id;
  final String code;
  final String nameBn;
  final String nameEn;
  final int bcsMarks;

  /// Marks in the selected exam track's pattern (from a track overview).
  final int? trackMarks;
  final String? icon;
  final String? colorHex;
  final int questionCount;
  final double? mastery;
  final List<Topic> topics;

  String name(BuildContext context) => context.isBn ? nameBn : nameEn;
  Color get color => AppColors.fromHex(colorHex);
  IconData get iconData => subjectIcons[icon] ?? Icons.menu_book_rounded;

  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'name_bn': nameBn,
    'name_en': nameEn,
    'bcs_marks': bcsMarks,
    'track_marks': trackMarks,
    'icon': icon,
    'color': colorHex,
    'question_count': questionCount,
    'mastery': mastery,
    'topics': topics.map((t) => t.toJson()).toList(),
  };
}

/// Icon names stored in the database → Material icons (const, tree-shakeable).
const subjectIcons = <String, IconData>{
  'menu_book': Icons.menu_book_rounded,
  'translate': Icons.translate_rounded,
  'flag': Icons.flag_rounded,
  'public': Icons.public_rounded,
  'terrain': Icons.terrain_rounded,
  'science': Icons.science_rounded,
  'computer': Icons.computer_rounded,
  'calculate': Icons.calculate_rounded,
  'psychology': Icons.psychology_rounded,
  'balance': Icons.balance_rounded,
};

@immutable
class ExamSchedule {
  const ExamSchedule({
    required this.id,
    required this.examType,
    required this.titleBn,
    required this.titleEn,
    required this.expectedDate,
    required this.isConfirmed,
    this.sourceUrl,
  });

  factory ExamSchedule.fromJson(Map<String, dynamic> j) => ExamSchedule(
    id: j.integer('id'),
    examType: j.str('exam_type'),
    titleBn: j.str('title_bn'),
    titleEn: j.str('title_en'),
    expectedDate: j.dateOr('expected_date', DateTime.now()),
    isConfirmed: j.boolean('is_confirmed'),
    sourceUrl: j.strOrNull('source_url'),
  );

  final int id;
  final String examType;
  final String titleBn;
  final String titleEn;
  final DateTime expectedDate;
  final bool isConfirmed;
  final String? sourceUrl;

  String title(BuildContext context) => context.isBn ? titleBn : titleEn;
  int get daysLeft => expectedDate.difference(DateTime.now()).inDays.clamp(0, 100000);

  Map<String, dynamic> toJson() => {
    'id': id,
    'exam_type': examType,
    'title_bn': titleBn,
    'title_en': titleEn,
    'expected_date': expectedDate.toIso8601String(),
    'is_confirmed': isConfirmed,
    'source_url': sourceUrl,
  };
}

class CatalogRepository {
  CatalogRepository(this._client, this._cache);

  final SupabaseClient _client;
  final CachedFetcher _cache;

  /// Subjects + topics + the caller's mastery. User-specific → 15 min cache.
  /// With a [track]: only that track's subjects, with its marks and question
  /// counts.
  Future<List<Subject>> subjects({bool force = false, String? track}) {
    final uid = _client.auth.currentUser?.id;
    return _cache.get<List<Subject>>(
      'subjects:${uid ?? 'anon'}${track == null ? '' : ':$track'}',
      forceRefresh: force,
      fetch: () async {
        final rows = await _client.rpcList('get_subjects_overview', params: {'p_track': ?track});
        return rows.map(Subject.fromJson).toList();
      },
      encode: (v) => v.map((s) => s.toJson()).toList(),
      decode: (j) => (j! as List).map((e) => Subject.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      isEmpty: (v) => v.isEmpty,
    );
  }

  Future<List<ExamSchedule>> schedules() {
    return _cache.get<List<ExamSchedule>>(
      'exam_schedules',
      fetch: () async {
        final rows = await guard(
          () => _client
              .from('exam_schedules')
              .select('id, exam_type, title_bn, title_en, expected_date, is_confirmed, source_url')
              .eq('is_active', true)
              .order('expected_date'),
        );
        return rows.map(ExamSchedule.fromJson).toList();
      },
      encode: (v) => v.map((s) => s.toJson()).toList(),
      decode: (j) => (j! as List).map((e) => ExamSchedule.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      policy: CachePolicy.long,
      isEmpty: (v) => v.isEmpty,
    );
  }

  /// The exam tracks (BCS, bank, other jobs) and their model-test patterns.
  Future<List<ExamTrack>> tracks() {
    return _cache.get<List<ExamTrack>>(
      'exam_tracks',
      fetch: () async {
        final rows = await guard(
          () => _client.from('exam_tracks').select(ExamTrack.columns).eq('is_active', true).order('sort'),
        );
        return rows.map(ExamTrack.fromJson).toList();
      },
      encode: (v) => v.map((t) => t.toJson()).toList(),
      decode: (j) => (j! as List).map((e) => ExamTrack.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      policy: CachePolicy.catalog,
      isEmpty: (v) => v.isEmpty,
    );
  }

  Future<void> invalidateSubjects() => _cache.invalidatePrefix('subjects:');
}

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(ref.watch(supabaseProvider), ref.watch(cachedFetcherProvider)),
);

final subjectsProvider = FutureProvider<List<Subject>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(catalogRepositoryProvider).subjects();
});

final subjectByIdProvider = Provider.family<Subject?, int>((ref, id) {
  final list = ref.watch(subjectsProvider).value;
  if (list == null) return null;
  for (final s in list) {
    if (s.id == id) return s;
  }
  return null;
});

final examSchedulesProvider = FutureProvider<List<ExamSchedule>>(
  (ref) => ref.watch(catalogRepositoryProvider).schedules(),
);

/// The exam tracks; the built-in patterns until fetched (and when offline).
final examTracksProvider = FutureProvider<List<ExamTrack>>((ref) async {
  try {
    final list = await ref.watch(catalogRepositoryProvider).tracks();
    return list.isEmpty ? ExamTrack.defaults : list;
  } on Object {
    return ExamTrack.defaults;
  }
});

/// The section (BCS / bank / other jobs) the question bank and model tests
/// show. Remembered on this device; starts from the learner's target exam.
class SelectedTrackNotifier extends Notifier<String> {
  static const _key = 'catalog:selected_track';

  @override
  String build() {
    final saved = ref.read(cacheStoreProvider).read(_key)?.data;
    if (saved is String && ExamTrack.defaults.any((t) => t.code == saved)) return saved;
    final targets = ref.watch(currentProfileProvider.select((p) => p.value?.targetExams)) ?? const <String>[];
    return ExamTrack.forTargetExams(targets);
  }

  Future<void> select(String code) async {
    state = code;
    await ref.read(cacheStoreProvider).write(_key, code, const Duration(days: 3650));
  }
}

final selectedTrackProvider = NotifierProvider<SelectedTrackNotifier, String>(SelectedTrackNotifier.new);

/// The selected track's pattern (server copy when loaded, else built-in).
final selectedExamTrackProvider = Provider<ExamTrack>((ref) {
  final code = ref.watch(selectedTrackProvider);
  final list = ref.watch(examTracksProvider).value ?? ExamTrack.defaults;
  for (final t in [...list, ...ExamTrack.defaults]) {
    if (t.code == code) return t;
  }
  return ExamTrack.defaults.first;
});

/// A track's subjects with its marks and question counts.
final trackSubjectsProvider = FutureProvider.family<List<Subject>, String>((ref, track) {
  ref.watch(currentUserIdProvider);
  return ref.watch(catalogRepositoryProvider).subjects(track: track);
});
