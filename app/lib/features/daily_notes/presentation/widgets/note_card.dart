import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/daily_notes/data/daily_note.dart';
import 'package:prostuti/features/daily_notes/presentation/widgets/note_category_style.dart';
import 'package:url_launcher/url_launcher.dart';

/// A daily note: category, importance, title, summary, key facts, probable
/// questions with tap-to-reveal answers, sources and a bookmark toggle.
class NoteCard extends StatefulWidget {
  const NoteCard({
    required this.note,
    this.bookmarked = false,
    this.bookmarkPending = false,
    this.onToggleBookmark,
    super.key,
  });

  final DailyNote note;
  final bool bookmarked;

  /// The last bookmark change is queued offline (shows a small clock).
  final bool bookmarkPending;
  final VoidCallback? onToggleBookmark;

  @override
  State<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<NoteCard> with AutomaticKeepAliveClientMixin {
  bool _questionsOpen = false;
  final _revealed = <int>{};

  // Keep the card's expand/reveal state when it scrolls off screen.
  @override
  bool get wantKeepAlive => _questionsOpen || _revealed.isNotEmpty;

  void _toggleQuestions() {
    setState(() => _questionsOpen = !_questionsOpen);
    updateKeepAlive();
  }

  void _reveal(int index) {
    setState(() => _revealed.add(index));
    updateKeepAlive();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final note = widget.note;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l = context.l10n;
    final accent = noteCategoryColor(note.category, theme.brightness);
    final bangla = context.isBn;
    final summary = note.summaryFor(bangla: bangla);
    final facts = note.keyFactsFor(bangla: bangla);
    final questions = note.questionsFor(bangla: bangla);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.xs, Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: Gap.sm,
                    runSpacing: Gap.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      NoteCategoryPill(category: note.category),
                      ImportanceBadge(level: note.importance),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: widget.onToggleBookmark,
                  tooltip: widget.bookmarked ? l.dailyNotesBookmarkRemove : l.dailyNotesBookmarkAdd,
                  isSelected: widget.bookmarked,
                  icon: Badge(
                    isLabelVisible: widget.bookmarkPending,
                    backgroundColor: Colors.transparent,
                    alignment: AlignmentDirectional.bottomEnd,
                    offset: const Offset(2, 2),
                    label: Icon(Icons.schedule_rounded, size: 11, color: scheme.onSurfaceVariant),
                    child: Icon(
                      widget.bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                      color: widget.bookmarked ? scheme.primary : null,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: Gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Gap.h4,
                  Text(
                    note.titleFor(bangla: bangla),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (summary.isNotEmpty) ...[
                    Gap.h8,
                    Text(
                      summary,
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurface.withValues(alpha: 0.85)),
                    ),
                  ],
                  if (facts.isNotEmpty) ...[Gap.h16, _KeyFacts(facts: facts, accent: accent)],
                  if (questions.isNotEmpty) ...[
                    Gap.h12,
                    _ProbableQuestions(
                      questions: questions,
                      open: _questionsOpen,
                      revealed: _revealed,
                      onToggle: _toggleQuestions,
                      onReveal: _reveal,
                    ),
                  ],
                  if (note.sourceLinks.isNotEmpty) ...[Gap.h12, _Sources(sources: note.sourceLinks)],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 1–5 importance as a coloured pill ("অবশ্যই জানুন", "গুরুত্বপূর্ণ" …).
class ImportanceBadge extends StatelessWidget {
  const ImportanceBadge({required this.level, super.key});

  final int level;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final label = noteImportanceLabel(l, level);
    final (color, icon) = switch (level) {
      >= 5 => (scheme.error, Icons.local_fire_department_rounded),
      4 => (readableWarning(Theme.of(context).brightness), Icons.bolt_rounded),
      3 => (scheme.primary, Icons.star_rounded),
      _ => (scheme.onSurfaceVariant, Icons.info_outline_rounded),
    };
    return Semantics(
      label: l.dailyNotesImportanceSemantics(context.n(level)),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(100)),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 18, color: c),
        Gap.w8,
        Expanded(
          child: Text(label, style: theme.textTheme.labelLarge?.copyWith(color: c)),
        ),
      ],
    );
  }
}

class _KeyFacts extends StatelessWidget {
  const _KeyFacts({required this.facts, required this.accent});

  final List<NoteFact> facts;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, Gap.xs),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: theme.brightness == Brightness.dark ? 0.10 : 0.06),
        borderRadius: const BorderRadius.all(Radii.md),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(icon: Icons.checklist_rounded, label: context.l10n.dailyNotesKeyFacts, color: accent),
          Gap.h8,
          for (final fact in facts)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 9),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                    ),
                  ),
                  Gap.w8,
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: fact.fact),
                          if (fact.tag != null) ...[
                            const TextSpan(text: '  '),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest,
                                  borderRadius: const BorderRadius.all(Radii.sm),
                                ),
                                child: Text(
                                  fact.tag!,
                                  style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ProbableQuestions extends StatelessWidget {
  const _ProbableQuestions({
    required this.questions,
    required this.open,
    required this.revealed,
    required this.onToggle,
    required this.onReveal,
  });

  final List<ProbableQuestion> questions;
  final bool open;
  final Set<int> revealed;
  final VoidCallback onToggle;
  final ValueChanged<int> onReveal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l = context.l10n;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radii.md),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: const BorderRadius.all(Radii.md),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                child: Row(
                  children: [
                    Icon(Icons.quiz_rounded, size: 18, color: scheme.primary),
                    Gap.w8,
                    Expanded(
                      child: Text(
                        l.dailyNotesProbableQuestions(context.n(questions.length)),
                        style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
                      ),
                    ),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.expand_more_rounded, color: scheme.primary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !open
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < questions.length; i++) ...[
                          if (i > 0) const Divider(height: Gap.xl),
                          _QuestionItem(
                            index: i,
                            question: questions[i],
                            revealed: revealed.contains(i),
                            onReveal: () => onReveal(i),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _QuestionItem extends StatelessWidget {
  const _QuestionItem({required this.index, required this.question, required this.revealed, required this.onReveal});

  final int index;
  final ProbableQuestion question;
  final bool revealed;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${context.n(index + 1)}. ${question.question}',
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        Gap.h8,
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: revealed
              ? Container(
                  key: const ValueKey('answer'),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: const BorderRadius.all(Radii.sm),
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${l.dailyNotesAnswer}: ',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: question.answer),
                      ],
                    ),
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              : Material(
                  key: const ValueKey('hidden'),
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: const BorderRadius.all(Radii.sm),
                  child: InkWell(
                    onTap: onReveal,
                    borderRadius: const BorderRadius.all(Radii.sm),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44, minWidth: double.infinity),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
                        child: Row(
                          children: [
                            Icon(Icons.visibility_rounded, size: 18, color: scheme.onSurfaceVariant),
                            Gap.w8,
                            Expanded(
                              child: Text(
                                l.dailyNotesShowAnswer,
                                style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _Sources extends StatelessWidget {
  const _Sources({required this.sources});

  final List<SourceLink> sources;

  Future<void> _open(BuildContext context, SourceLink source) async {
    final uri = source.uri;
    var ok = false;
    if (uri != null) {
      try {
        ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } on Object {
        ok = false;
      }
    }
    if (!ok && context.mounted) showInfoSnack(context, context.l10n.dailyNotesOpenLinkFailed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(icon: Icons.newspaper_rounded, label: l.dailyNotesSources),
        Gap.h8,
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            for (final source in sources)
              ActionChip(
                avatar: Icon(Icons.open_in_new_rounded, size: 16, color: theme.colorScheme.primary),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Text(source.label, overflow: TextOverflow.ellipsis),
                ),
                tooltip: l.dailyNotesOpenSource(source.title ?? source.label),
                onPressed: () => _open(context, source),
              ),
          ],
        ),
      ],
    );
  }
}
