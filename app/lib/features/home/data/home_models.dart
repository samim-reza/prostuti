import 'package:flutter/foundation.dart';
import 'package:prostuti/core/utils/json.dart';
import 'package:prostuti/features/study_plan/data/plan_models.dart' show pickLocalized;

/// A note title in both languages.
@immutable
class NoteHeadline {
  const NoteHeadline({required this.titleBn, this.titleEn, this.category});

  final String titleBn;
  final String? titleEn;
  final String? category;

  String title({required bool bangla}) => pickLocalized(bangla: bangla, bn: titleBn, en: titleEn);

  Map<String, dynamic> toJson() => {'title': titleBn, 'title_en': titleEn, 'category': category};
}

@immutable
class DailyExamInfo {
  const DailyExamInfo({
    required this.id,
    required this.titleBn,
    this.titleEn,
    this.questionCount = 0,
    this.durationMinutes = 0,
  });

  factory DailyExamInfo.fromJson(Map<String, dynamic> j) => DailyExamInfo(
    id: j.integer('id'),
    titleBn: j.str('title_bn'),
    titleEn: j.strOrNull('title_en'),
    questionCount: j.integer('question_count'),
    durationMinutes: j.integer('duration_minutes'),
  );

  final int id;
  final String titleBn;
  final String? titleEn;
  final int questionCount;
  final int durationMinutes;

  String title({required bool bangla}) => pickLocalized(bangla: bangla, bn: titleBn, en: titleEn);

  Map<String, dynamic> toJson() => {
    'id': id,
    'title_bn': titleBn,
    'title_en': titleEn,
    'question_count': questionCount,
    'duration_minutes': durationMinutes,
  };
}

/// What Home shows from `get_today_notes()`: a count, the top headlines
/// (already ordered by importance) and today's daily exam. Only the summary
/// is cached, not the full notes.
@immutable
class NotesDigest {
  const NotesDigest({this.noteDate, this.count = 0, this.top = const [], this.dailyExam});

  factory NotesDigest.fromRpc(Map<String, dynamic> j, {int top = 3}) {
    final notes = j.list('notes', (n) => n);
    return NotesDigest(
      noteDate: j.strOrNull('note_date'),
      count: notes.length,
      top: [
        for (final n in notes.take(top))
          NoteHeadline(titleBn: n.str('title'), titleEn: n.strOrNull('title_en'), category: n.strOrNull('category')),
      ],
      dailyExam: j.objOrNull('daily_exam') == null ? null : DailyExamInfo.fromJson(j.obj('daily_exam')),
    );
  }

  factory NotesDigest.fromJson(Map<String, dynamic> j) => NotesDigest(
    noteDate: j.strOrNull('note_date'),
    count: j.integer('count'),
    top: j.list(
      'top',
      (n) => NoteHeadline(titleBn: n.str('title'), titleEn: n.strOrNull('title_en'), category: n.strOrNull('category')),
    ),
    dailyExam: j.objOrNull('daily_exam') == null ? null : DailyExamInfo.fromJson(j.obj('daily_exam')),
  );

  final String? noteDate;
  final int count;
  final List<NoteHeadline> top;
  final DailyExamInfo? dailyExam;

  bool get isEmpty => count == 0 && dailyExam == null;

  Map<String, dynamic> toJson() => {
    'note_date': noteDate,
    'count': count,
    'top': top.map((t) => t.toJson()).toList(),
    'daily_exam': dailyExam?.toJson(),
  };
}

/// The user's free trial, if that is their only active entitlement.
@immutable
class TrialInfo {
  const TrialInfo({required this.addonCode, required this.expiresAt});

  final String addonCode;
  final DateTime expiresAt;

  bool isActive(DateTime now) => expiresAt.isAfter(now);

  /// Whole days remaining, rounded up (23 h left → 1 day).
  int daysLeft(DateTime now) {
    final d = expiresAt.difference(now);
    if (d.isNegative) return 0;
    return (d.inMinutes / (24 * 60)).ceil();
  }

  Map<String, dynamic> toJson() => {'addon_code': addonCode, 'expires_at': expiresAt.toUtc().toIso8601String()};

  static TrialInfo? fromJson(Map<String, dynamic> j) {
    final expires = j.date('expires_at');
    if (expires == null) return null;
    return TrialInfo(addonCode: j.str('addon_code'), expiresAt: expires);
  }
}

/// From the user's entitlement rows: the trial to advertise, or null when
/// there is no active trial or the user already has a paid/promo/admin one.
TrialInfo? trialFromEntitlements(List<Map<String, dynamic>> rows, DateTime now) {
  TrialInfo? best;
  for (final r in rows) {
    final expires = r.date('expires_at');
    if (expires == null || !expires.isAfter(now)) continue;
    final source = r.str('source');
    if (source != 'trial') return null;
    if (best == null || expires.isAfter(best.expiresAt)) {
      best = TrialInfo(addonCode: r.str('addon_code'), expiresAt: expires);
    }
  }
  return best;
}

/// Cacheable wrapper (a missing trial is a valid, cacheable answer).
@immutable
class TrialStatus {
  const TrialStatus(this.trial);

  factory TrialStatus.fromJson(Map<String, dynamic> j) =>
      TrialStatus(j.objOrNull('trial') == null ? null : TrialInfo.fromJson(j.obj('trial')));

  static const none = TrialStatus(null);

  final TrialInfo? trial;

  Map<String, dynamic> toJson() => {'trial': trial?.toJson()};
}
