import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:prostuti/core/utils/json.dart';

/// Parses a Postgres `date` (`yyyy-MM-dd`) or timestamp into a pure calendar
/// date (UTC midnight), so comparisons with `BdTime.today()` are exact.
DateTime? parsePlanDate(Object? raw) {
  if (raw == null) return null;
  final d = DateTime.tryParse(raw.toString());
  if (d == null) return null;
  return DateTime.utc(d.year, d.month, d.day);
}

String? _isoDate(DateTime? d) => d == null
    ? null
    : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// English text when the UI is English and it exists; Bangla otherwise.
String pickLocalized({required bool bangla, required String bn, String? en}) =>
    (!bangla && en != null && en.trim().isNotEmpty) ? en : bn;

bool _truthy(Object? v) => v == true || v == 1 || v == 'true' || v == 't';

/// Accepts a JSON list, a JSON-encoded string or anything else (→ empty).
List<Object?> _looseList(Object? raw) {
  if (raw is List) return raw;
  if (raw is String && raw.trim().startsWith('[')) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded;
    } on FormatException {
      return const [];
    }
  }
  return const [];
}

Map<String, dynamic>? _looseMap(Object? raw) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is String && raw.trim().startsWith('{')) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      return null;
    }
  }
  return null;
}

/// What the user does for a routine item.
enum PlanItemType {
  read,
  practice,
  exam,
  revise,
  rest,
  other;

  static PlanItemType parse(String? v) => values.firstWhere((e) => e.name == v, orElse: () => other);
}

/// The planner's day kinds (mirrors the SQL check constraint).
enum PlanDayKind {
  study('study'),
  revision('revision'),
  weakTopicExam('weak_topic_exam'),
  modelTest('model_test'),
  rest('rest'),
  other('other');

  PlanDayKind(this.wire);
  final String wire;

  static PlanDayKind parse(String? v) => values.firstWhere((e) => e.wire == v, orElse: () => other);
}

enum PlanDayStatus {
  pending,
  partial,
  done,
  missed;

  static PlanDayStatus parse(String? v) => values.firstWhere((e) => e.name == v, orElse: () => pending);
}

/// One checklist entry of a day's routine.
@immutable
class PlanItem {
  const PlanItem({
    required this.key,
    required this.type,
    required this.titleBn,
    this.titleEn,
    this.subjectId,
    this.topicId,
    this.minutes,
    this.count,
    this.route,
    this.done = false,
  });

  factory PlanItem.fromJson(Map<String, dynamic> j) => PlanItem(
    key: j.str('key'),
    type: PlanItemType.parse(j.strOrNull('type')),
    titleBn: j.str('title_bn', j.str('title')),
    titleEn: j.strOrNull('title_en'),
    subjectId: j.intOrNull('subject_id'),
    topicId: j.intOrNull('topic_id'),
    minutes: j.intOrNull('minutes'),
    count: j.intOrNull('count'),
    route: j.strOrNull('route'),
    done: _truthy(j['done']),
  );

  /// Tolerates a missing/garbled `items` column: non-map entries are skipped.
  static List<PlanItem> listFrom(Object? raw) =>
      _looseList(raw)
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => PlanItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();

  final String key;
  final PlanItemType type;
  final String titleBn;
  final String? titleEn;
  final int? subjectId;
  final int? topicId;
  final int? minutes;
  final int? count;

  /// In-app screen the planner links this item to (`/notes`, `/wrong-answers`…).
  final String? route;
  final bool done;

  /// The server marks items by key; an item without one can't be completed.
  bool get canComplete => key.isNotEmpty && type != PlanItemType.rest;

  String title({required bool bangla}) => pickLocalized(bangla: bangla, bn: titleBn, en: titleEn);

  PlanItem copyWith({bool? done}) => PlanItem(
    key: key,
    type: type,
    titleBn: titleBn,
    titleEn: titleEn,
    subjectId: subjectId,
    topicId: topicId,
    minutes: minutes,
    count: count,
    route: route,
    done: done ?? this.done,
  );

  Map<String, dynamic> toJson() => {
    'key': key,
    'type': type.name,
    'title_bn': titleBn,
    'title_en': titleEn,
    'subject_id': subjectId,
    'topic_id': topicId,
    'minutes': minutes,
    'count': count,
    'route': route,
    'done': done,
  };
}

/// Lowest-mastery topics, resolved on weak-topic exam days.
@immutable
class WeakTopic {
  const WeakTopic({required this.topicId, required this.nameBn, required this.nameEn, this.subjectId, this.mastery});

  factory WeakTopic.fromJson(Map<String, dynamic> j) => WeakTopic(
    topicId: j.integer('topic_id', j.integer('id')),
    nameBn: j.str('name_bn'),
    nameEn: j.str('name_en', j.str('name_bn')),
    subjectId: j.intOrNull('subject_id'),
    mastery: j.dblOrNull('mastery'),
  );

  final int topicId;
  final String nameBn;
  final String nameEn;
  final int? subjectId;

  /// 0…1.
  final double? mastery;

  String name({required bool bangla}) => pickLocalized(bangla: bangla, bn: nameBn, en: nameEn);

  Map<String, dynamic> toJson() => {
    'topic_id': topicId,
    'name_bn': nameBn,
    'name_en': nameEn,
    'subject_id': subjectId,
    'mastery': mastery,
  };
}

/// A visible day of the plan (today … today+2, or a past day).
@immutable
class PlanDay {
  const PlanDay({
    required this.id,
    required this.date,
    required this.kind,
    required this.titleBn,
    this.titleEn,
    this.planId,
    this.dayIndex = 0,
    this.items = const [],
    this.targetMinutes = 0,
    this.completedItems = 0,
    this.totalItems = 0,
    this.status = PlanDayStatus.pending,
    this.weakTopics = const [],
  });

  factory PlanDay.fromJson(Map<String, dynamic> j) {
    final items = PlanItem.listFrom(j['items']);
    return PlanDay(
      id: j.integer('id'),
      planId: j.strOrNull('plan_id'),
      date: parsePlanDate(j['day_date']) ?? DateTime.utc(1970),
      dayIndex: j.integer('day_index'),
      kind: PlanDayKind.parse(j.strOrNull('kind')),
      titleBn: j.str('title_bn'),
      titleEn: j.strOrNull('title_en'),
      items: items,
      targetMinutes: j.integer('target_minutes'),
      completedItems: j.integer('completed_items', items.where((i) => i.done).length),
      totalItems: j.integer('total_items', items.length),
      status: PlanDayStatus.parse(j.strOrNull('status')),
      weakTopics: _looseList(j['weak_topics'])
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => WeakTopic.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  final int id;
  final String? planId;
  final DateTime date;
  final int dayIndex;
  final PlanDayKind kind;
  final String titleBn;
  final String? titleEn;
  final List<PlanItem> items;
  final int targetMinutes;
  final int completedItems;
  final int totalItems;
  final PlanDayStatus status;
  final List<WeakTopic> weakTopics;

  String title({required bool bangla}) => pickLocalized(bangla: bangla, bn: titleBn, en: titleEn);

  int get doneCount => items.isEmpty ? completedItems : items.where((i) => i.done).length;
  int get itemCount => items.isEmpty ? totalItems : items.length;

  double get progress {
    if (itemCount == 0) return status == PlanDayStatus.done ? 1 : 0;
    return (doneCount / itemCount).clamp(0, 1).toDouble();
  }

  /// Planned minutes (falls back to the sum of item minutes).
  int get plannedMinutes => targetMinutes > 0 ? targetMinutes : items.fold<int>(0, (sum, i) => sum + (i.minutes ?? 0));

  bool isUnlockedOn(DateTime bdToday) => !date.isAfter(bdToday);

  PlanDay copyWith({List<PlanItem>? items, int? completedItems, PlanDayStatus? status, List<WeakTopic>? weakTopics}) =>
      PlanDay(
        id: id,
        planId: planId,
        date: date,
        dayIndex: dayIndex,
        kind: kind,
        titleBn: titleBn,
        titleEn: titleEn,
        items: items ?? this.items,
        targetMinutes: targetMinutes,
        completedItems: completedItems ?? this.completedItems,
        totalItems: totalItems,
        status: status ?? this.status,
        weakTopics: weakTopics ?? this.weakTopics,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'plan_id': planId,
    'day_date': _isoDate(date),
    'day_index': dayIndex,
    'kind': kind.wire,
    'title_bn': titleBn,
    'title_en': titleEn,
    'items': items.map((i) => i.toJson()).toList(),
    'target_minutes': targetMinutes,
    'completed_items': completedItems,
    'total_items': totalItems,
    'status': status.name,
    'weak_topics': weakTopics.map((w) => w.toJson()).toList(),
  };
}

/// Pure reducer used for optimistic updates: marks [key] as (un)done and
/// recomputes the counters exactly like `_complete_plan_item` does in SQL.
PlanDay setItemDone(PlanDay day, String key, {bool done = true}) {
  if (key.isEmpty || !day.items.any((i) => i.key == key && i.done != done)) return day;
  final items = [
    for (final item in day.items)
      if (item.key == key) item.copyWith(done: done) else item,
  ];
  final doneCount = items.where((i) => i.done).length;
  final total = day.totalItems > 0 ? day.totalItems : items.length;
  final status = doneCount >= total && total > 0
      ? PlanDayStatus.done
      : doneCount > 0
      ? PlanDayStatus.partial
      : (day.status == PlanDayStatus.missed ? PlanDayStatus.missed : PlanDayStatus.pending);
  return day.copyWith(items: items, completedItems: doneCount, status: status);
}

/// Brief day row (overview timeline / upcoming days).
@immutable
class PlanDayBrief {
  const PlanDayBrief({
    required this.id,
    required this.date,
    required this.kind,
    required this.titleBn,
    this.titleEn,
    this.targetMinutes = 0,
    this.status = PlanDayStatus.pending,
    this.completedItems = 0,
    this.totalItems = 0,
  });

  factory PlanDayBrief.fromJson(Map<String, dynamic> j) => PlanDayBrief(
    id: j.integer('id'),
    date: parsePlanDate(j['day_date']) ?? DateTime.utc(1970),
    kind: PlanDayKind.parse(j.strOrNull('kind')),
    titleBn: j.str('title_bn'),
    titleEn: j.strOrNull('title_en'),
    targetMinutes: j.integer('target_minutes'),
    status: PlanDayStatus.parse(j.strOrNull('status')),
    completedItems: j.integer('completed_items'),
    totalItems: j.integer('total_items'),
  );

  final int id;
  final DateTime date;
  final PlanDayKind kind;
  final String titleBn;
  final String? titleEn;
  final int targetMinutes;
  final PlanDayStatus status;
  final int completedItems;
  final int totalItems;

  String title({required bool bangla}) => pickLocalized(bangla: bangla, bn: titleBn, en: titleEn);

  double get progress =>
      totalItems == 0 ? (status == PlanDayStatus.done ? 1 : 0) : (completedItems / totalItems).clamp(0, 1).toDouble();

  Map<String, dynamic> toJson() => {
    'id': id,
    'day_date': _isoDate(date),
    'kind': kind.wire,
    'title_bn': titleBn,
    'title_en': titleEn,
    'target_minutes': targetMinutes,
    'status': status.name,
    'completed_items': completedItems,
    'total_items': totalItems,
  };
}

/// The active plan's header fields.
@immutable
class PlanInfo {
  const PlanInfo({
    required this.id,
    this.examDate,
    this.startDate,
    this.daysLeft,
    this.dailyMinutes = 0,
    this.version = 1,
  });

  factory PlanInfo.fromJson(Map<String, dynamic> j) => PlanInfo(
    id: j.str('id'),
    examDate: parsePlanDate(j['exam_date']),
    startDate: parsePlanDate(j['start_date']),
    daysLeft: j.intOrNull('days_left'),
    dailyMinutes: j.integer('daily_minutes'),
    version: j.integer('version', 1),
  );

  final String id;
  final DateTime? examDate;
  final DateTime? startDate;
  final int? daysLeft;
  final int dailyMinutes;
  final int version;

  Map<String, dynamic> toJson() => {
    'id': id,
    'exam_date': _isoDate(examDate),
    'start_date': _isoDate(startDate),
    'days_left': daysLeft,
    'daily_minutes': dailyMinutes,
    'version': version,
  };
}

/// `get_today_routine()` — everything Home needs about today in one call.
@immutable
class TodayRoutine {
  const TodayRoutine({required this.hasPlan, this.plan, this.today, this.upcoming = const []});

  factory TodayRoutine.fromJson(Map<String, dynamic> j) {
    final planJson = _looseMap(j['plan']);
    final todayJson = _looseMap(j['today']);
    return TodayRoutine(
      hasPlan: j.boolean('has_plan', planJson != null),
      plan: planJson == null ? null : PlanInfo.fromJson(planJson),
      today: todayJson == null ? null : PlanDay.fromJson(todayJson),
      upcoming: _looseList(j['upcoming'])
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => PlanDayBrief.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  static const empty = TodayRoutine(hasPlan: false);

  final bool hasPlan;
  final PlanInfo? plan;
  final PlanDay? today;
  final List<PlanDayBrief> upcoming;

  TodayRoutine withToday(PlanDay? day) => TodayRoutine(hasPlan: hasPlan, plan: plan, today: day, upcoming: upcoming);

  Map<String, dynamic> toJson() => {
    'has_plan': hasPlan,
    'plan': plan?.toJson(),
    'today': today?.toJson(),
    'upcoming': upcoming.map((d) => d.toJson()).toList(),
  };
}

@immutable
class PlanPhase {
  const PlanPhase({
    required this.key,
    required this.nameBn,
    this.nameEn,
    this.startDate,
    this.endDate,
    this.focusBn,
    this.focusEn,
  });

  factory PlanPhase.fromJson(Map<String, dynamic> j) => PlanPhase(
    key: j.str('key'),
    nameBn: j.str('name_bn', j.str('name', j.str('name_en'))),
    nameEn: j.strOrNull('name_en'),
    startDate: parsePlanDate(j['start_date']),
    endDate: parsePlanDate(j['end_date']),
    focusBn: j.strOrNull('focus_bn') ?? j.strOrNull('focus'),
    focusEn: j.strOrNull('focus_en'),
  );

  final String key;
  final String nameBn;
  final String? nameEn;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? focusBn;
  final String? focusEn;

  String name({required bool bangla}) => pickLocalized(bangla: bangla, bn: nameBn, en: nameEn);

  String? focus({required bool bangla}) {
    final f = pickLocalized(bangla: bangla, bn: focusBn ?? '', en: focusEn);
    return f.trim().isEmpty ? null : f;
  }

  bool isCurrent(DateTime today) =>
      startDate != null && endDate != null && !today.isBefore(startDate!) && !today.isAfter(endDate!);

  bool isPast(DateTime today) => endDate != null && today.isAfter(endDate!);

  Map<String, dynamic> toJson() => {
    'key': key,
    'name_bn': nameBn,
    'name_en': nameEn,
    'start_date': _isoDate(startDate),
    'end_date': _isoDate(endDate),
    'focus_bn': focusBn,
    'focus_en': focusEn,
  };
}

@immutable
class PlanMilestone {
  const PlanMilestone({required this.titleBn, this.titleEn, this.date});

  factory PlanMilestone.fromJson(Map<String, dynamic> j) => PlanMilestone(
    titleBn: j.str('title_bn', j.str('title', j.str('title_en'))),
    titleEn: j.strOrNull('title_en'),
    date: parsePlanDate(j['date']),
  );

  final String titleBn;
  final String? titleEn;
  final DateTime? date;

  String title({required bool bangla}) => pickLocalized(bangla: bangla, bn: titleBn, en: titleEn);

  Map<String, dynamic> toJson() => {'title_bn': titleBn, 'title_en': titleEn, 'date': _isoDate(date)};
}

/// `study_plans.summary` as produced by the planner (every field optional).
@immutable
class PlanSummary {
  const PlanSummary({this.phases = const [], this.milestones = const [], this.totalDays, this.weeklyHours});

  factory PlanSummary.parse(Object? raw) {
    final j = _looseMap(raw);
    if (j == null) return const PlanSummary();
    List<T> listOf<T>(String key, T Function(Map<String, dynamic>) map) =>
        _looseList(j[key]).whereType<Map<dynamic, dynamic>>().map((e) => map(Map<String, dynamic>.from(e))).toList();
    final phases = listOf('phases', PlanPhase.fromJson).where((p) => p.nameBn.isNotEmpty).toList();
    final milestones = listOf('milestones', PlanMilestone.fromJson).where((m) => m.titleBn.isNotEmpty).toList()
      ..sort((a, b) => (a.date ?? DateTime.utc(9999)).compareTo(b.date ?? DateTime.utc(9999)));
    return PlanSummary(
      phases: phases,
      milestones: milestones,
      totalDays: j.intOrNull('total_days'),
      weeklyHours: j.dblOrNull('weekly_hours'),
    );
  }

  final List<PlanPhase> phases;
  final List<PlanMilestone> milestones;
  final int? totalDays;
  final double? weeklyHours;

  bool get isEmpty => phases.isEmpty && milestones.isEmpty;

  Map<String, dynamic> toJson() => {
    'phases': phases.map((p) => p.toJson()).toList(),
    'milestones': milestones.map((m) => m.toJson()).toList(),
    'total_days': totalDays,
    'weekly_hours': weeklyHours,
  };
}

/// Tips may arrive as plain strings or as `{text|tip_bn|title_bn}` objects.
List<String> parseAiTips(Object? raw) {
  final out = <String>[];
  for (final e in _looseList(raw)) {
    if (e is String && e.trim().isNotEmpty) {
      out.add(e.trim());
    } else if (e is Map) {
      final text = const [
        'text',
        'tip_bn',
        'title_bn',
        'tip',
      ].map((k) => e[k]).whereType<String>().firstWhere((v) => v.trim().isNotEmpty, orElse: () => '');
      if (text.isNotEmpty) out.add(text.trim());
    }
  }
  return out;
}

/// `get_plan_overview()` — the WHOLE plan as aggregates (details stay hidden).
@immutable
class PlanOverview {
  const PlanOverview({
    required this.hasPlan,
    this.id,
    this.examDate,
    this.startDate,
    this.version = 1,
    this.dailyMinutes = 0,
    this.totalDays = 0,
    this.daysLeft = 0,
    this.doneDays = 0,
    this.partialDays = 0,
    this.missedDays = 0,
    this.lockedDays = 0,
    this.kinds = const {},
    this.summary = const PlanSummary(),
    this.aiTips = const [],
    this.recent = const [],
  });

  factory PlanOverview.fromJson(Map<String, dynamic> j) {
    final hasPlan = j.boolean('has_plan');
    if (!hasPlan) return none;
    final kinds = <String, int>{};
    _looseMap(j['kinds'])?.forEach((k, v) {
      final n = v is num ? v.toInt() : int.tryParse('$v');
      if (n != null) kinds[k] = n;
    });
    return PlanOverview(
      hasPlan: true,
      id: j.strOrNull('id'),
      examDate: parsePlanDate(j['exam_date']),
      startDate: parsePlanDate(j['start_date']),
      version: j.integer('version', 1),
      dailyMinutes: j.integer('daily_minutes'),
      totalDays: j.integer('total_days'),
      daysLeft: j.integer('days_left'),
      doneDays: j.integer('done_days'),
      partialDays: j.integer('partial_days'),
      missedDays: j.integer('missed_days'),
      lockedDays: j.integer('locked_days'),
      kinds: kinds,
      summary: PlanSummary.parse(j['summary']),
      aiTips: parseAiTips(j['ai_tips']),
      recent:
          _looseList(j['recent'])
              .whereType<Map<dynamic, dynamic>>()
              .map((e) => PlanDayBrief.fromJson(Map<String, dynamic>.from(e)))
              .toList()
            ..sort((a, b) => a.date.compareTo(b.date)),
    );
  }

  static const none = PlanOverview(hasPlan: false);

  final bool hasPlan;
  final String? id;
  final DateTime? examDate;
  final DateTime? startDate;
  final int version;
  final int dailyMinutes;
  final int totalDays;
  final int daysLeft;
  final int doneDays;
  final int partialDays;
  final int missedDays;
  final int lockedDays;
  final Map<String, int> kinds;
  final PlanSummary summary;
  final List<String> aiTips;
  final List<PlanDayBrief> recent;

  /// Share of plan days fully completed (0…1).
  double get completion => totalDays == 0 ? 0 : (doneDays / totalDays).clamp(0, 1).toDouble();

  Map<String, dynamic> toJson() => {
    'has_plan': hasPlan,
    'id': id,
    'exam_date': _isoDate(examDate),
    'start_date': _isoDate(startDate),
    'version': version,
    'daily_minutes': dailyMinutes,
    'total_days': totalDays,
    'days_left': daysLeft,
    'done_days': doneDays,
    'partial_days': partialDays,
    'missed_days': missedDays,
    'locked_days': lockedDays,
    'kinds': kinds,
    'summary': summary.toJson(),
    'ai_tips': aiTips,
    'recent': recent.map((d) => d.toJson()).toList(),
  };
}
