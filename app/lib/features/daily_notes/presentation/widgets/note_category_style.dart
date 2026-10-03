import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/features/daily_notes/data/daily_note.dart';

/// Localized label for a note category.
String noteCategoryLabel(AppLocalizations l, NoteCategory category) => switch (category) {
  NoteCategory.bangladesh => l.dailyNotesCatBangladesh,
  NoteCategory.international => l.dailyNotesCatInternational,
  NoteCategory.economy => l.dailyNotesCatEconomy,
  NoteCategory.scienceTech => l.dailyNotesCatScienceTech,
  NoteCategory.sports => l.dailyNotesCatSports,
  NoteCategory.environment => l.dailyNotesCatEnvironment,
  NoteCategory.awardsPeople => l.dailyNotesCatAwardsPeople,
  NoteCategory.organizations => l.dailyNotesCatOrganizations,
  NoteCategory.daysEvents => l.dailyNotesCatDaysEvents,
  NoteCategory.misc => l.dailyNotesCatMisc,
};

IconData noteCategoryIcon(NoteCategory category) => switch (category) {
  NoteCategory.bangladesh => Icons.flag_rounded,
  NoteCategory.international => Icons.public_rounded,
  NoteCategory.economy => Icons.trending_up_rounded,
  NoteCategory.scienceTech => Icons.biotech_rounded,
  NoteCategory.sports => Icons.sports_cricket_rounded,
  NoteCategory.environment => Icons.eco_rounded,
  NoteCategory.awardsPeople => Icons.emoji_events_rounded,
  NoteCategory.organizations => Icons.account_balance_rounded,
  NoteCategory.daysEvents => Icons.event_rounded,
  NoteCategory.misc => Icons.lightbulb_rounded,
};

/// Base hue per category (print + light theme).
Color noteCategoryBaseColor(NoteCategory category) => switch (category) {
  NoteCategory.bangladesh => const Color(0xFF006A4E),
  NoteCategory.international => const Color(0xFF2F6FDE),
  NoteCategory.economy => const Color(0xFFB7791F),
  NoteCategory.scienceTech => const Color(0xFF7A4BD6),
  NoteCategory.sports => const Color(0xFFD9480F),
  NoteCategory.environment => const Color(0xFF2E8B57),
  NoteCategory.awardsPeople => const Color(0xFFC2255C),
  NoteCategory.organizations => const Color(0xFF1F7A9C),
  NoteCategory.daysEvents => const Color(0xFFD7263D),
  NoteCategory.misc => const Color(0xFF5F6B7A),
};

/// Category colour tuned for the current brightness (lighter on dark
/// surfaces so text and icons keep enough contrast).
Color noteCategoryColor(NoteCategory category, Brightness brightness) {
  final base = noteCategoryBaseColor(category);
  return brightness == Brightness.dark ? Color.lerp(base, Colors.white, 0.38)! : base;
}

/// Short label for a 1–5 importance level.
String noteImportanceLabel(AppLocalizations l, int level) => switch (level) {
  >= 5 => l.dailyNotesImportanceTop,
  4 => l.dailyNotesImportanceHigh,
  3 => l.dailyNotesImportanceMedium,
  _ => l.dailyNotesImportanceLow,
};

/// Amber that stays readable as text: the brand warning colour on dark
/// surfaces, a deeper shade on light ones.
Color readableWarning(Brightness brightness) =>
    brightness == Brightness.dark ? const Color(0xFFF2B84B) : const Color(0xFF9C5D00);

/// Small rounded label with the category icon and name.
class NoteCategoryPill extends StatelessWidget {
  const NoteCategoryPill({required this.category, super.key});

  final NoteCategory category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = noteCategoryColor(category, theme.brightness);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: const BorderRadius.all(Radius.circular(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(noteCategoryIcon(category), size: 15, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              noteCategoryLabel(context.l10n, category),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
