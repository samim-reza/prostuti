import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/cache/cached_fetcher.dart';
import 'package:prostuti/core/network/rpc.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/utils/json.dart';
import 'package:prostuti/features/profile/data/profile.dart';

/// Allowed range of `profiles.daily_study_minutes` (check constraint).
const minStudyMinutes = 15;
const maxStudyMinutes = 960;

/// Editable profile fields (only columns the client may update).
@immutable
class ProfileDraft {
  const ProfileDraft({
    required this.fullName,
    required this.username,
    required this.bio,
    required this.district,
    required this.occupation,
    required this.targetExams,
    required this.targetScheduleId,
    required this.dailyStudyMinutes,
    required this.allowMessagesFrom,
  });

  factory ProfileDraft.fromProfile(Profile p) => ProfileDraft(
    fullName: p.fullName ?? '',
    username: p.username,
    bio: p.bio ?? '',
    district: p.district,
    occupation: p.occupation ?? '',
    targetExams: p.targetExams,
    targetScheduleId: p.targetScheduleId,
    dailyStudyMinutes: p.dailyStudyMinutes,
    allowMessagesFrom: p.allowMessagesFrom,
  );

  final String fullName;
  final String username;
  final String bio;
  final String? district;
  final String occupation;
  final List<String> targetExams;
  final int? targetScheduleId;
  final int dailyStudyMinutes;
  final String allowMessagesFrom;
}

String? _clean(String? v) {
  final t = v?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

/// Minimal update for `profiles`: only changed, client-writable columns, with
/// text trimmed and blank optional fields stored as null. An empty map means
/// "nothing to save".
Map<String, dynamic> buildProfilePatch(Profile original, ProfileDraft draft) {
  final patch = <String, dynamic>{};
  void text(String column, String? before, String? after) {
    final a = _clean(after);
    if (a != _clean(before)) patch[column] = a;
  }

  text('full_name', original.fullName, draft.fullName);
  final username = draft.username.trim();
  if (username.isNotEmpty && username != original.username) patch['username'] = username;
  text('bio', original.bio, draft.bio);
  text('district', original.district, draft.district);
  text('occupation', original.occupation, draft.occupation);
  if (!setEquals(original.targetExams.toSet(), draft.targetExams.toSet()) && draft.targetExams.isNotEmpty) {
    patch['target_exams'] = draft.targetExams;
  }
  if (draft.targetScheduleId != original.targetScheduleId) patch['target_schedule_id'] = draft.targetScheduleId;
  final minutes = draft.dailyStudyMinutes.clamp(minStudyMinutes, maxStudyMinutes);
  if (minutes != original.dailyStudyMinutes) patch['daily_study_minutes'] = minutes;
  if (draft.allowMessagesFrom != original.allowMessagesFrom &&
      const {'friends', 'everyone'}.contains(draft.allowMessagesFrom)) {
    patch['allow_messages_from'] = draft.allowMessagesFrom;
  }
  return patch;
}

/// `public.exam_types` row (BCS, bank, primary …).
@immutable
class ExamTypeInfo {
  const ExamTypeInfo({required this.code, required this.nameBn, required this.nameEn});

  factory ExamTypeInfo.fromJson(Map<String, dynamic> j) =>
      ExamTypeInfo(code: j.str('code'), nameBn: j.str('name_bn'), nameEn: j.str('name_en', j.str('name_bn')));

  final String code;
  final String nameBn;
  final String nameEn;

  String name({required bool bangla}) => bangla ? nameBn : nameEn;

  Map<String, dynamic> toJson() => {'code': code, 'name_bn': nameBn, 'name_en': nameEn};
}

/// Exam types for the "target exams" chips (reference data, cached a day).
final examTypesProvider = FutureProvider<List<ExamTypeInfo>>((ref) {
  final client = ref.watch(supabaseProvider);
  return ref
      .watch(cachedFetcherProvider)
      .get<List<ExamTypeInfo>>(
        'exam_types',
        fetch: () async {
          final rows = await guard(() => client.from('exam_types').select('code, name_bn, name_en').order('sort'));
          return rows.map(ExamTypeInfo.fromJson).toList(growable: false);
        },
        encode: (v) => v.map((e) => e.toJson()).toList(),
        decode: (j) => (j! as List).map((e) => ExamTypeInfo.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        policy: CachePolicy.catalog,
        isEmpty: (v) => v.isEmpty,
      );
});

/// Result of the live username check.
enum UsernameStatus { unchanged, invalid, checking, available, taken, unknown }
