import 'package:flutter/material.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_theme.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/features/daily_notes/data/daily_note.dart';
import 'package:prostuti/features/daily_notes/presentation/widgets/note_category_style.dart';

// Print-designed blocks for the notes PDF. They are rendered off-screen by
// `PdfExportService` (no Localizations/Navigator above them), so every string
// arrives pre-localized and every colour is explicit: white paper, dark ink,
// identical in light and dark mode. The off-screen view has a very tall max
// height, so every Column is `MainAxisSize.min` (content-sized blocks).

const _ink = Color(0xFF1B1F1D);
const _inkSoft = Color(0xFF4A524E);
const _inkMuted = Color(0xFF7A837F);
const _rule = Color(0xFFDCE3E0);
const _paper = Colors.white;

final ThemeData _printTheme = AppTheme.light();

/// Wraps a block in the light theme + print text style.
class _Paper extends StatelessWidget {
  const _Paper({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _printTheme,
      child: DefaultTextStyle(
        style: const TextStyle(fontFamily: AppTheme.fontFamily, color: _ink, fontSize: 11, height: 1.5),
        child: ColoredBox(color: _paper, child: child),
      ),
    );
  }
}

/// Strings used by the print blocks (resolved from `AppLocalizations`).
@immutable
class NotesPrintStrings {
  const NotesPrintStrings({
    required this.brand,
    required this.tagline,
    required this.dateLabel,
    required this.countLabel,
    required this.keyFacts,
    required this.probableQuestions,
    required this.answer,
    required this.sources,
    required this.footer,
    required this.downloadedBy,
    required this.categoryLabel,
    required this.importanceLabel,
    required this.bangla,
  });

  final String brand;
  final String tagline;
  final String dateLabel;
  final String countLabel;
  final String keyFacts;

  /// Section title without a count ("সম্ভাব্য প্রশ্ন").
  final String probableQuestions;
  final String answer;
  final String sources;
  final String footer;
  final String downloadedBy;
  final String Function(NoteCategory category) categoryLabel;
  final String Function(int level) importanceLabel;
  final bool bangla;
}

class NotesPrintHeader extends StatelessWidget {
  const NotesPrintHeader({required this.strings, super.key});

  final NotesPrintStrings strings;

  @override
  Widget build(BuildContext context) {
    return _Paper(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: const BoxDecoration(
              color: AppColors.brand,
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                  child: const Icon(Icons.newspaper_rounded, color: Colors.white, size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.brand,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      Text(strings.tagline, style: const TextStyle(color: Color(0xFFD5EFE6), fontSize: 9.5)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      strings.dateLabel,
                      style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                    Text(strings.countLabel, style: const TextStyle(color: Color(0xFFD5EFE6), fontSize: 9.5)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class NotePrintBlock extends StatelessWidget {
  const NotePrintBlock({required this.note, required this.index, required this.strings, super.key});

  final DailyNote note;

  /// 1-based position in the document.
  final int index;
  final NotesPrintStrings strings;

  @override
  Widget build(BuildContext context) {
    final accent = noteCategoryBaseColor(note.category);
    final bangla = strings.bangla;
    String n(Object v) => Fmt.digits(v, bangla: bangla);
    final summary = note.summaryFor(bangla: bangla);
    final facts = note.keyFactsFor(bangla: bangla);
    final questions = note.questionsFor(bangla: bangla);
    return _Paper(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: _paper,
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          border: Border.all(color: _rule),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  child: Text(
                    n(index),
                    style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(noteCategoryIcon(note.category), size: 13, color: accent),
                const SizedBox(width: 4),
                Text(
                  strings.categoryLabel(note.category),
                  style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  strings.importanceLabel(note.importance),
                  style: const TextStyle(color: _inkMuted, fontSize: 9.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              note.titleFor(bangla: bangla),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.4),
            ),
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(summary, style: const TextStyle(color: _inkSoft)),
            ],
            if (facts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.06),
                  border: Border(left: BorderSide(color: accent, width: 2.5)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PrintHeading(text: strings.keyFacts, color: accent),
                    for (final fact in facts)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Container(
                                width: 4.5,
                                height: 4.5,
                                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                              ),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(text: fact.fact),
                                    if (fact.tag != null)
                                      TextSpan(
                                        text: '  [${fact.tag}]',
                                        style: const TextStyle(color: _inkMuted, fontSize: 9.5),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (questions.isNotEmpty) ...[
              const SizedBox(height: 8),
              _PrintHeading(text: strings.probableQuestions, color: AppColors.brand),
              for (var i = 0; i < questions.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${n(i + 1)}. ${questions[i].question}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 14),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${strings.answer}: ',
                                style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700),
                              ),
                              TextSpan(text: questions[i].answer),
                            ],
                          ),
                          style: const TextStyle(color: _inkSoft),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (note.sourceLinks.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Divider(height: 1, thickness: 0.6, color: _rule),
              const SizedBox(height: 5),
              Text(
                '${strings.sources}: ${note.sourceLinks.map((s) => s.title == null ? s.label : '${s.label} — ${s.title}').join(' · ')}',
                style: const TextStyle(color: _inkMuted, fontSize: 9, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PrintHeading extends StatelessWidget {
  const _PrintHeading({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700),
    );
  }
}

class NotesPrintFooter extends StatelessWidget {
  const NotesPrintFooter({required this.strings, super.key});

  final NotesPrintStrings strings;

  @override
  Widget build(BuildContext context) {
    return _Paper(
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Divider(height: 1, thickness: 0.8, color: _rule),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.verified_rounded, size: 14, color: AppColors.brand),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(strings.footer, style: const TextStyle(color: _inkMuted, fontSize: 9.5)),
                ),
                const SizedBox(width: 8),
                Text(
                  strings.downloadedBy,
                  style: const TextStyle(color: _inkSoft, fontSize: 9.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
