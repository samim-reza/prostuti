import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/features/daily_notes/data/daily_note.dart';
import 'package:prostuti/features/daily_notes/presentation/notes_download_flow.dart';
import 'package:prostuti/features/daily_notes/presentation/widgets/countdown_chip.dart';
import 'package:prostuti/features/daily_notes/presentation/widgets/note_category_style.dart';

/// Date, subtitle, note count and the "removed at midnight" countdown.
class NotesHeader extends StatelessWidget {
  const NotesHeader({required this.today, this.onDayEnded, super.key});

  final TodayNotes today;
  final VoidCallback? onDayEnded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l = context.l10n;
    final date = today.date;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      date == null ? today.noteDate : notesLongDate(date, bangla: context.isBn),
                      style: theme.textTheme.titleLarge,
                    ),
                    Gap.h4,
                    Text(
                      l.dailyNotesSubtitle,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Gap.w12,
              Container(
                padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 6),
                decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.1), borderRadius: Radii.chip),
                child: Text(
                  l.dailyNotesNoteCount(context.n(today.notes.length)),
                  style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
                ),
              ),
            ],
          ),
          Gap.h12,
          RemovalCountdownChip(onDayEnded: onDayEnded),
        ],
      ),
    );
  }
}

/// "আজকের সাম্প্রতিক পরীক্ষা" call to action.
class DailyExamCtaCard extends StatelessWidget {
  const DailyExamCtaCard({required this.exam, super.key});

  final DailyExamInfo exam;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l = context.l10n;
    final bangla = context.isBn;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: scheme.primaryContainer.withValues(alpha: theme.brightness == Brightness.dark ? 0.35 : 0.6),
      child: InkWell(
        onTap: () => context.push(Routes.dailyExam),
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: scheme.primary, borderRadius: const BorderRadius.all(Radii.md)),
                child: Icon(Icons.timer_rounded, color: scheme.onPrimary),
              ),
              Gap.w12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.dailyNotesExamCtaTitle, style: theme.textTheme.titleSmall),
                    Gap.h4,
                    Text(
                      l.dailyNotesExamCtaBody(
                        context.n(exam.questionCount),
                        Fmt.minutes(exam.durationMinutes, bangla: bangla),
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Gap.w8,
              Text(l.dailyNotesExamCtaAction, style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary)),
              Icon(Icons.chevron_right_rounded, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pinned, horizontally scrolling category chips with per-category counts.
class CategoryFilterBarDelegate extends SliverPersistentHeaderDelegate {
  const CategoryFilterBarDelegate({
    required this.counts,
    required this.total,
    required this.selected,
    required this.onSelected,
  });

  final Map<NoteCategory, int> counts;
  final int total;
  final NoteCategory? selected;
  final ValueChanged<NoteCategory?> onSelected;

  static const _height = 60.0;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final entries = counts.entries.toList(growable: false);
    return Material(
      color: theme.scaffoldBackgroundColor,
      elevation: overlapsContent || shrinkOffset > 0 ? 1 : 0,
      shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.3),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.sm + 2),
        itemCount: entries.length + 1,
        separatorBuilder: (_, _) => Gap.w8,
        itemBuilder: (context, i) {
          if (i == 0) {
            return ChoiceChip(
              label: Text('${l.dailyNotesFilterAll} · ${context.n(total)}'),
              selected: selected == null,
              showCheckmark: false,
              onSelected: (_) => onSelected(null),
            );
          }
          final MapEntry(key: category, value: count) = entries[i - 1];
          final color = noteCategoryColor(category, theme.brightness);
          final isSelected = selected == category;
          return ChoiceChip(
            avatar: Icon(
              noteCategoryIcon(category),
              size: 16,
              color: isSelected ? color : color.withValues(alpha: 0.8),
            ),
            label: Text('${noteCategoryLabel(l, category)} · ${context.n(count)}'),
            selected: isSelected,
            showCheckmark: false,
            selectedColor: color.withValues(alpha: 0.18),
            side: BorderSide(color: isSelected ? color : theme.colorScheme.outlineVariant),
            onSelected: (_) => onSelected(category),
          );
        },
      ),
    );
  }

  @override
  bool shouldRebuild(CategoryFilterBarDelegate oldDelegate) =>
      oldDelegate.selected != selected || oldDelegate.total != total || oldDelegate.counts != counts;
}

/// "Keep today's notes on your phone" — download as PDF.
class NotesDownloadCard extends StatelessWidget {
  const NotesDownloadCard({required this.downloaded, required this.needsAd, required this.onDownload, super.key});

  final bool downloaded;
  final bool needsAd;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l = context.l10n;
    return Card(
      child: Padding(
        padding: Gap.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.error.withValues(alpha: 0.1),
                    borderRadius: const BorderRadius.all(Radii.md),
                  ),
                  child: Icon(Icons.picture_as_pdf_rounded, color: scheme.error),
                ),
                Gap.w12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.dailyNotesDownloadPdf, style: theme.textTheme.titleSmall),
                      Text(
                        l.dailyNotesDownloadHint,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Gap.h12,
            FilledButton.tonalIcon(
              onPressed: onDownload,
              icon: Icon(needsAd ? Icons.ondemand_video_rounded : Icons.download_rounded),
              label: Text(downloaded ? l.dailyNotesDownloadAgain : l.dailyNotesDownloadPdf),
            ),
          ],
        ),
      ),
    );
  }
}

/// Blocking progress overlay (ad loading, PDF rendering).
class BusyOverlay extends StatelessWidget {
  const BusyOverlay({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: Stack(
        children: [
          ModalBarrier(dismissible: false, color: Colors.black.withValues(alpha: 0.45)),
          Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.xl, vertical: Gap.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 3)),
                    Gap.h16,
                    Text(message, style: theme.textTheme.titleSmall, textAlign: TextAlign.center),
                    Gap.h4,
                    Text(
                      context.l10n.dailyNotesPleaseWait,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
