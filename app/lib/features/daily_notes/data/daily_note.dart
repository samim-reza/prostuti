import 'package:flutter/foundation.dart';
import 'package:prostuti/core/utils/json.dart';

/// Note categories (mirror the `daily_notes.category` check constraint).
enum NoteCategory {
  bangladesh,
  international,
  economy,
  scienceTech('science_tech'),
  sports,
  environment,
  awardsPeople('awards_people'),
  organizations,
  daysEvents('days_events'),
  misc;

  NoteCategory([this._wire]);
  final String? _wire;

  /// Value stored in Postgres.
  String get wire => _wire ?? name;

  /// Unknown or missing values fall back to [misc] so a new backend category
  /// never crashes an older app.
  static NoteCategory parse(String? value) =>
      NoteCategory.values.firstWhere((c) => c.wire == value, orElse: () => NoteCategory.misc);
}

/// One exam-relevant fact inside a note (`key_facts[]`).
@immutable
class NoteFact {
  const NoteFact({required this.fact, this.tag});

  /// Accepts `{fact, tag?}` objects and, defensively, bare strings.
  factory NoteFact.fromAny(Object? raw) {
    if (raw is Map) {
      final j = Map<String, dynamic>.from(raw);
      final tag = j.strOrNull('tag')?.trim();
      return NoteFact(fact: j.str('fact', j.str('text')).trim(), tag: (tag?.isEmpty ?? true) ? null : tag);
    }
    return NoteFact(fact: raw?.toString().trim() ?? '');
  }

  final String fact;
  final String? tag;

  Map<String, dynamic> toJson() => {'fact': fact, 'tag': ?tag};

  @override
  bool operator ==(Object other) => other is NoteFact && other.fact == fact && other.tag == tag;

  @override
  int get hashCode => Object.hash(fact, tag);
}

/// A likely exam question with its answer (`probable_questions[]`).
@immutable
class ProbableQuestion {
  const ProbableQuestion({required this.question, required this.answer});

  factory ProbableQuestion.fromJson(Map<String, dynamic> j) =>
      ProbableQuestion(question: j.str('q', j.str('question')).trim(), answer: j.str('a', j.str('answer')).trim());

  final String question;
  final String answer;

  Map<String, dynamic> toJson() => {'q': question, 'a': answer};
}

/// A newspaper article the note was built from (`source_links[]`).
@immutable
class SourceLink {
  const SourceLink({required this.url, this.title, this.source});

  factory SourceLink.fromJson(Map<String, dynamic> j) {
    String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    return SourceLink(
      url: j.str('url').trim(),
      title: clean(j.strOrNull('title')),
      source: clean(j.strOrNull('source')),
    );
  }

  final String url;
  final String? title;
  final String? source;

  /// Short chip label: outlet name, else the host of the URL.
  String get label {
    if (source != null) return source!;
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.isNotEmpty) return host.replaceFirst(RegExp(r'^www\.'), '');
    return title ?? url;
  }

  /// Only http(s) links are opened (defence against odd AI output).
  Uri? get uri {
    final u = Uri.tryParse(url);
    if (u == null || !(u.isScheme('http') || u.isScheme('https'))) return null;
    return u;
  }

  Map<String, dynamic> toJson() => {'url': url, 'title': ?title, 'source': ?source};
}

/// A daily current-affairs note.
@immutable
class DailyNote {
  const DailyNote({
    required this.id,
    required this.category,
    required this.title,
    required this.summary,
    this.noteDate,
    this.keyFacts = const [],
    this.probableQuestions = const [],
    this.titleEn,
    this.summaryEn,
    this.keyFactsEn = const [],
    this.probableQuestionsEn = const [],
    this.importance = 3,
    this.sourceLinks = const [],
    this.createdAt,
  });

  factory DailyNote.fromJson(Map<String, dynamic> j) => DailyNote(
    id: j.integer('id'),
    noteDate: j.strOrNull('note_date'),
    category: NoteCategory.parse(j.strOrNull('category')),
    title: j.str('title').trim(),
    summary: j.str('summary').trim(),
    keyFacts: _facts(j['key_facts']),
    probableQuestions: _questions(j['probable_questions']),
    titleEn: _blankToNull(j.strOrNull('title_en')),
    summaryEn: _blankToNull(j.strOrNull('summary_en')),
    keyFactsEn: _facts(j['key_facts_en']),
    probableQuestionsEn: _questions(j['probable_questions_en']),
    importance: j.integer('importance', 3).clamp(1, 5),
    sourceLinks: _rawList(j['source_links'])
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => SourceLink.fromJson(Map<String, dynamic>.from(m)))
        .where((s) => s.url.isNotEmpty)
        .toList(growable: false),
    createdAt: j.date('created_at'),
  );

  final int id;

  /// `yyyy-MM-dd` (present in bookmarks payloads; implied by [TodayNotes]).
  final String? noteDate;
  final NoteCategory category;
  final String title;
  final String summary;
  final List<NoteFact> keyFacts;
  final List<ProbableQuestion> probableQuestions;

  /// English translations (filled by the AI pipeline; may be missing).
  final String? titleEn;
  final String? summaryEn;
  final List<NoteFact> keyFactsEn;
  final List<ProbableQuestion> probableQuestionsEn;

  /// 1 (nice to know) … 5 (must know).
  final int importance;
  final List<SourceLink> sourceLinks;
  final DateTime? createdAt;

  // Localized views: English when the UI is English and a translation
  // exists, otherwise the Bangla original (field by field).
  String titleFor({required bool bangla}) => bangla ? title : (titleEn ?? title);
  String summaryFor({required bool bangla}) => bangla ? summary : (summaryEn ?? summary);
  List<NoteFact> keyFactsFor({required bool bangla}) => (bangla || keyFactsEn.isEmpty) ? keyFacts : keyFactsEn;
  List<ProbableQuestion> questionsFor({required bool bangla}) =>
      (bangla || probableQuestionsEn.isEmpty) ? probableQuestions : probableQuestionsEn;

  DailyNote withDate(String date) => DailyNote(
    id: id,
    noteDate: date,
    category: category,
    title: title,
    summary: summary,
    keyFacts: keyFacts,
    probableQuestions: probableQuestions,
    titleEn: titleEn,
    summaryEn: summaryEn,
    keyFactsEn: keyFactsEn,
    probableQuestionsEn: probableQuestionsEn,
    importance: importance,
    sourceLinks: sourceLinks,
    createdAt: createdAt,
  );

  /// Same shape as `get_today_notes()` items, so it doubles as the cache
  /// encoding and as the bookmark payload (bookmarked notes stay readable
  /// after the day ends, when RLS hides the row).
  Map<String, dynamic> toJson() => {
    'id': id,
    'note_date': ?noteDate,
    'category': category.wire,
    'title': title,
    'summary': summary,
    'key_facts': keyFacts.map((f) => f.toJson()).toList(),
    'probable_questions': probableQuestions.map((q) => q.toJson()).toList(),
    'title_en': titleEn,
    'summary_en': summaryEn,
    'key_facts_en': keyFactsEn.map((f) => f.toJson()).toList(),
    'probable_questions_en': probableQuestionsEn.map((q) => q.toJson()).toList(),
    'importance': importance,
    'source_links': sourceLinks.map((s) => s.toJson()).toList(),
    'created_at': ?createdAt?.toUtc().toIso8601String(),
  };
}

/// Summary of today's daily exam (`get_today_notes().daily_exam`).
@immutable
class DailyExamInfo {
  const DailyExamInfo({
    required this.id,
    required this.title,
    required this.questionCount,
    required this.durationMinutes,
    this.titleEn,
  });

  factory DailyExamInfo.fromJson(Map<String, dynamic> j) => DailyExamInfo(
    id: j.integer('id'),
    title: j.str('title_bn'),
    titleEn: _blankToNull(j.strOrNull('title_en')),
    questionCount: j.integer('question_count'),
    durationMinutes: j.integer('duration_minutes', 10),
  );

  final int id;

  /// Bangla title (`title_bn`).
  final String title;
  final String? titleEn;
  final int questionCount;
  final int durationMinutes;

  String titleFor({required bool bangla}) => bangla ? title : (titleEn ?? title);

  Map<String, dynamic> toJson() => {
    'id': id,
    'title_bn': title,
    'title_en': titleEn,
    'question_count': questionCount,
    'duration_minutes': durationMinutes,
  };
}

/// Everything the current-affairs screens need for today, in one payload.
@immutable
class TodayNotes {
  const TodayNotes({required this.noteDate, this.notes = const [], this.downloaded = false, this.dailyExam});

  factory TodayNotes.fromJson(Map<String, dynamic> j) {
    final date = j.str('note_date');
    return TodayNotes(
      noteDate: date,
      notes: j.list('notes', DailyNote.fromJson).map((n) => n.noteDate == null ? n.withDate(date) : n).toList(),
      downloaded: j.boolean('downloaded'),
      dailyExam: j.objOrNull('daily_exam') == null ? null : DailyExamInfo.fromJson(j.obj('daily_exam')),
    );
  }

  /// `yyyy-MM-dd` Bangladesh date of the notes.
  final String noteDate;
  final List<DailyNote> notes;

  /// Whether the user already claimed today's PDF download.
  final bool downloaded;
  final DailyExamInfo? dailyExam;

  bool get isEmpty => notes.isEmpty;

  /// Notes or the exam haven't been published yet → refetch soon instead of
  /// caching "nothing" until midnight.
  bool get isIncomplete => notes.isEmpty || dailyExam == null;

  /// Calendar date of the notes (UTC-flagged, Bangladesh wall clock).
  DateTime? get date {
    final d = DateTime.tryParse(noteDate);
    return d == null ? null : DateTime.utc(d.year, d.month, d.day);
  }

  /// Categories present today, in canonical order, with their note counts.
  Map<NoteCategory, int> get categoryCounts {
    final counts = <NoteCategory, int>{};
    for (final n in notes) {
      counts[n.category] = (counts[n.category] ?? 0) + 1;
    }
    return {
      for (final c in NoteCategory.values)
        if (counts[c] != null) c: counts[c]!,
    };
  }

  List<DailyNote> filtered(NoteCategory? category) =>
      category == null ? notes : notes.where((n) => n.category == category).toList(growable: false);

  TodayNotes copyWith({bool? downloaded}) =>
      TodayNotes(noteDate: noteDate, notes: notes, downloaded: downloaded ?? this.downloaded, dailyExam: dailyExam);

  Map<String, dynamic> toJson() => {
    'note_date': noteDate,
    'notes': notes.map((n) => n.toJson()).toList(),
    'downloaded': downloaded,
    'daily_exam': dailyExam?.toJson(),
  };
}

List<Object?> _rawList(Object? value) => value is List ? value : const [];

String? _blankToNull(String? value) {
  final v = value?.trim();
  return (v == null || v.isEmpty) ? null : v;
}

List<NoteFact> _facts(Object? raw) =>
    _rawList(raw).map(NoteFact.fromAny).where((f) => f.fact.isNotEmpty).toList(growable: false);

List<ProbableQuestion> _questions(Object? raw) =>
    _rawList(raw)
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => ProbableQuestion.fromJson(Map<String, dynamic>.from(m)))
        .where((q) => q.question.isNotEmpty)
        .toList(growable: false);
