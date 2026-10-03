import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/features/daily_notes/application/downloaded_files.dart';
import 'package:prostuti/features/daily_notes/application/today_notes_controller.dart';
import 'package:prostuti/features/daily_notes/data/daily_note.dart';
import 'package:prostuti/features/daily_notes/data/daily_notes_repository.dart';

Map<String, dynamic> _payload() => {
  'note_date': '2026-10-04',
  'downloaded': true,
  'daily_exam': {
    'id': 7,
    'title_bn': 'দৈনিক সাম্প্রতিক পরীক্ষা',
    'title_en': 'Daily current affairs exam',
    'question_count': 20,
    'duration_minutes': 10,
  },
  'notes': [
    {
      'id': 11,
      'category': 'science_tech',
      'title': 'বাংলাদেশের দ্বিতীয় স্যাটেলাইট',
      'summary': 'সারসংক্ষেপ',
      'title_en': "Bangladesh's second satellite",
      'summary_en': '',
      'key_facts': [
        {'fact': 'উৎক্ষেপণ: ২০২৬', 'tag': 'সাল'},
        {'fact': 'নির্মাতা: থালেস'},
        'বেয়ার স্ট্রিং তথ্য',
        {'fact': '   '},
      ],
      'key_facts_en': [
        {'fact': 'Launch: 2026', 'tag': 'year'},
      ],
      'probable_questions': [
        {'q': 'কবে উৎক্ষেপণ?', 'a': '২০২৬'},
        {'q': '', 'a': 'ignored'},
      ],
      'probable_questions_en': <Object>[],
      'importance': 9,
      'source_links': [
        {'title': 'Prothom Alo report', 'url': 'https://www.prothomalo.com/a', 'source': 'Prothom Alo'},
        {'title': 'No url', 'url': ''},
        {'url': 'https://www.thedailystar.net/x'},
      ],
      'created_at': '2026-10-04T00:05:00Z',
    },
    {
      'id': 12,
      'category': 'sports',
      'title': 'ক্রিকেট',
      'summary': 'খেলা',
      'key_facts': null,
      'probable_questions': 'not a list',
      'importance': 3,
      'source_links': <Object>[],
    },
    {'id': 13, 'category': 'brand_new_category', 'title': 'নতুন', 'summary': 'x', 'importance': 0},
  ],
};

void main() {
  group('TodayNotes.fromJson', () {
    test('parses a full get_today_notes payload', () {
      final t = TodayNotes.fromJson(_payload());
      expect(t.noteDate, '2026-10-04');
      expect(t.date, DateTime.utc(2026, 10, 4));
      expect(t.downloaded, isTrue);
      expect(t.notes, hasLength(3));
      expect(t.isEmpty, isFalse);
      expect(t.isIncomplete, isFalse);

      final exam = t.dailyExam!;
      expect(exam.id, 7);
      expect(exam.questionCount, 20);
      expect(exam.durationMinutes, 10);
      expect(exam.titleFor(bangla: true), 'দৈনিক সাম্প্রতিক পরীক্ষা');
      expect(exam.titleFor(bangla: false), 'Daily current affairs exam');

      final n = t.notes.first;
      expect(n.id, 11);
      expect(n.noteDate, '2026-10-04', reason: 'notes inherit the payload date');
      expect(n.category, NoteCategory.scienceTech);
      expect(n.importance, 5, reason: 'clamped to 1..5');
      expect(n.keyFacts.map((f) => f.fact), ['উৎক্ষেপণ: ২০২৬', 'নির্মাতা: থালেস', 'বেয়ার স্ট্রিং তথ্য']);
      expect(n.keyFacts.first.tag, 'সাল');
      expect(n.keyFacts[1].tag, isNull);
      expect(n.probableQuestions, hasLength(1));
      expect(n.probableQuestions.single.answer, '২০২৬');
      expect(n.sourceLinks, hasLength(2), reason: 'links without url are dropped');
      expect(n.sourceLinks.first.label, 'Prothom Alo');
      expect(n.sourceLinks.last.label, 'thedailystar.net');
      expect(n.sourceLinks.first.uri, isNotNull);
      expect(n.createdAt, DateTime.utc(2026, 10, 4, 0, 5));
    });

    test('tolerates nulls, wrong types and unknown categories', () {
      final t = TodayNotes.fromJson(_payload());
      final sports = t.notes[1];
      expect(sports.keyFacts, isEmpty);
      expect(sports.probableQuestions, isEmpty);
      expect(sports.sourceLinks, isEmpty);
      final unknown = t.notes[2];
      expect(unknown.category, NoteCategory.misc);
      expect(unknown.importance, 1);
    });

    test('empty day: no notes, no exam', () {
      final t = TodayNotes.fromJson(const {
        'notes': <Object>[],
        'note_date': '2026-10-04',
        'daily_exam': null,
        'downloaded': false,
      });
      expect(t.isEmpty, isTrue);
      expect(t.isIncomplete, isTrue);
      expect(t.dailyExam, isNull);
      expect(t.downloaded, isFalse);
      expect(t.categoryCounts, isEmpty);
    });

    test('notes published but exam not yet → incomplete (short cache)', () {
      final json = _payload()..['daily_exam'] = null;
      expect(TodayNotes.fromJson(json).isIncomplete, isTrue);
    });

    test('round-trips through toJson (cache encoding)', () {
      final t = TodayNotes.fromJson(_payload());
      final again = TodayNotes.fromJson(t.toJson());
      expect(again.toJson(), t.toJson());
      expect(again.notes.first.keyFacts, t.notes.first.keyFacts);
      expect(again.notes.first.keyFactsEn, t.notes.first.keyFactsEn);
      expect(again.dailyExam!.titleEn, 'Daily current affairs exam');
    });

    test('copyWith(downloaded) keeps everything else', () {
      final t = TodayNotes.fromJson(_payload()).copyWith(downloaded: false);
      expect(t.downloaded, isFalse);
      expect(t.notes, hasLength(3));
      expect(t.dailyExam, isNotNull);
    });
  });

  group('bilingual fallback', () {
    test('English fields are used when present, Bangla otherwise', () {
      final n = TodayNotes.fromJson(_payload()).notes.first;
      expect(n.titleFor(bangla: false), "Bangladesh's second satellite");
      expect(n.titleFor(bangla: true), 'বাংলাদেশের দ্বিতীয় স্যাটেলাইট');
      // Blank English summary → Bangla.
      expect(n.summaryEn, isNull);
      expect(n.summaryFor(bangla: false), 'সারসংক্ষেপ');
      expect(n.keyFactsFor(bangla: false).single.fact, 'Launch: 2026');
      expect(n.keyFactsFor(bangla: true), hasLength(3));
      // Empty English questions → Bangla questions.
      expect(n.questionsFor(bangla: false).single.question, 'কবে উৎক্ষেপণ?');
    });

    test('bookmark payload keeps both languages', () {
      final json = TodayNotes.fromJson(_payload()).notes.first.toJson();
      expect(json['title_en'], "Bangladesh's second satellite");
      expect(json['key_facts_en'], isNotEmpty);
      expect(json['note_date'], '2026-10-04');
      expect(json['category'], 'science_tech');
    });
  });

  group('categories & filtering', () {
    test('parse maps every wire value', () {
      for (final c in NoteCategory.values) {
        expect(NoteCategory.parse(c.wire), c);
      }
      expect(NoteCategory.parse('awards_people'), NoteCategory.awardsPeople);
      expect(NoteCategory.parse('days_events'), NoteCategory.daysEvents);
      expect(NoteCategory.parse(null), NoteCategory.misc);
    });

    test('categoryCounts follow canonical order and filtered() narrows', () {
      final t = TodayNotes.fromJson(_payload());
      expect(t.categoryCounts.keys, [NoteCategory.scienceTech, NoteCategory.sports, NoteCategory.misc]);
      expect(t.filtered(NoteCategory.sports).single.id, 12);
      expect(t.filtered(null), hasLength(3));
      expect(t.filtered(NoteCategory.economy), isEmpty);
    });
  });

  group('todayNotesPolicy', () {
    test('ttl lasts until the end of the day', () {
      final p = todayNotesPolicy(const Duration(hours: 5));
      expect(p.ttl, const Duration(hours: 5));
      expect(p.negativeTtl, const Duration(minutes: 10));
    });

    test('at least one minute, negative never longer than ttl', () {
      final p = todayNotesPolicy(const Duration(seconds: 5));
      expect(p.ttl, const Duration(minutes: 1));
      expect(p.negativeTtl, const Duration(minutes: 1));
      expect(todayNotesPolicy(Duration.zero).ttl, const Duration(minutes: 1));
    });
  });

  group('downloaded files', () {
    test('notes date from file name', () {
      expect(notesDateFromFileName('/data/x/downloads/prostuti-notes-2026-10-04.pdf'), DateTime.utc(2026, 10, 4));
      expect(notesDateFromFileName('/data/x/downloads/exam-result.pdf'), isNull);
      expect(notesDateFromFileName('prostuti-notes-2026-13-04.pdf'), isNull);
      expect(fileBaseName('/a/b/prostuti-notes-2026-10-04.pdf'), 'prostuti-notes-2026-10-04.pdf');
    });

    test('file size parts', () {
      expect(fileSizeParts(500, bangla: false), (value: '1', megabytes: false));
      expect(fileSizeParts(240 * 1024, bangla: true), (value: '২৪০', megabytes: false));
      expect(fileSizeParts((1.4 * 1024 * 1024).round(), bangla: false), (value: '1.4', megabytes: true));
      expect(fileSizeParts(2 * 1024 * 1024, bangla: false), (value: '2', megabytes: true));
    });
  });

  group('NoteBookmarks.withPendingOps', () {
    test('queued toggles overlay the saved state and are marked pending', () {
      const saved = NoteBookmarks(ids: {'1', '2'});
      final merged = saved.withPendingOps({2: false, 3: true});
      expect(merged.ids, {'1', '3'});
      expect(merged.pending, {'2', '3'});
      expect(merged.contains(3), isTrue);
      expect(merged.isPending(1), isFalse);
    });
  });
}
