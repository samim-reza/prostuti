import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/app_image.dart';
import 'package:prostuti/features/bookmarks/data/bookmark.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:url_launcher/url_launcher.dart';

const _optionLabelsBn = ['ক', 'খ', 'গ', 'ঘ', 'ঙ'];
const _optionLabelsEn = ['A', 'B', 'C', 'D', 'E'];

/// Saved question with its correct answer and explanation.
class BookmarkQuestionCard extends ConsumerWidget {
  const BookmarkQuestionCard({required this.bookmark, super.key});
  final Bookmark bookmark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final q = BookmarkedQuestion.fromPayload(bookmark.payload);
    final subject = q.subjectId == null ? null : ref.watch(subjectByIdProvider(q.subjectId!));
    final labels = context.isBn ? _optionLabelsBn : _optionLabelsEn;
    final source = [if (q.sourceRef != null) q.sourceRef!, if (q.year != null) context.n(q.year!)].join(' · ');

    return Card(
      child: Padding(
        padding: Gap.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (subject != null) ...[
                  Icon(subject.iconData, size: 16, color: subject.color),
                  Gap.w4,
                  Flexible(
                    child: Text(
                      subject.name(context),
                      style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ] else
                  Text(l.bookmarksTabQuestions, style: theme.textTheme.labelMedium?.copyWith(color: scheme.primary)),
                const Spacer(),
                Text(
                  Fmt.timeAgo(bookmark.createdAt, bangla: context.isBn),
                  style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            Gap.h8,
            Text(q.stem, style: theme.textTheme.titleSmall),
            Gap.h12,
            for (var i = 0; i < q.options.length; i++)
              _OptionRow(
                label: i < labels.length ? labels[i] : context.n(i + 1),
                text: q.options[i],
                correct: q.correctIndex == i,
                wrongPick: q.selectedIndex == i && q.correctIndex != null && q.correctIndex != i,
              ),
            if (q.correctIndex == null) ...[
              Gap.h4,
              Text(
                l.bookmarksAnswerUnknown,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (q.explanation != null) ...[
              Gap.h8,
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Gap.md),
                decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.07), borderRadius: Radii.button),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb_outline_rounded, size: 18, color: scheme.primary),
                        Gap.w8,
                        Text(
                          l.bookmarksExplanation,
                          style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
                        ),
                      ],
                    ),
                    Gap.h4,
                    Text(q.explanation!, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
            if (source.isNotEmpty) ...[
              Gap.h8,
              Row(
                children: [
                  Icon(Icons.bookmark_border_rounded, size: 16, color: scheme.onSurfaceVariant),
                  Gap.w4,
                  Expanded(
                    child: Text(
                      l.bookmarksSource(source),
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.label, required this.text, required this.correct, required this.wrongPick});

  final String label;
  final String text;
  final bool correct;
  final bool wrongPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = correct ? AppColors.success : (wrongPick ? scheme.error : null);
    return Container(
      margin: const EdgeInsets.only(bottom: Gap.xs + 2),
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
      decoration: BoxDecoration(
        borderRadius: Radii.button,
        color: color?.withValues(alpha: 0.1),
        border: Border.all(color: color ?? scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: color ?? scheme.surfaceContainerHighest,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color == null ? scheme.onSurfaceVariant : Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Gap.w12,
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
          if (correct) const Icon(Icons.check_circle_rounded, size: 20, color: AppColors.success),
          if (wrongPick) Icon(Icons.cancel_rounded, size: 20, color: scheme.error),
        ],
      ),
    );
  }
}

/// Saved daily note — readable after its day has passed.
class BookmarkNoteCard extends StatefulWidget {
  const BookmarkNoteCard({required this.bookmark, super.key});
  final Bookmark bookmark;

  @override
  State<BookmarkNoteCard> createState() => _BookmarkNoteCardState();
}

class _BookmarkNoteCardState extends State<BookmarkNoteCard> {
  static const _collapsedFacts = 3;
  bool _expanded = false;

  String? _categoryLabel(AppLocalizations l, String? c) => switch (c) {
    'bangladesh' => l.bookmarksCatBangladesh,
    'international' => l.bookmarksCatInternational,
    'economy' => l.bookmarksCatEconomy,
    'science_tech' => l.bookmarksCatScience,
    'sports' => l.bookmarksCatSports,
    'environment' => l.bookmarksCatEnvironment,
    'awards_people' => l.bookmarksCatAwards,
    'organizations' => l.bookmarksCatOrganizations,
    'days_events' => l.bookmarksCatDays,
    'misc' => l.bookmarksCatMisc,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bangla = context.isBn;
    final note = BookmarkedNote.fromPayload(widget.bookmark.payload);
    final facts = note.factsFor(bangla: bangla);
    final visible = _expanded ? facts : facts.take(_collapsedFacts).toList();
    final category = _categoryLabel(l, note.category);
    final date = note.noteDate ?? widget.bookmark.createdAt;

    return Card(
      child: Padding(
        padding: Gap.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (category != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.xxs),
                    decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.1), borderRadius: Radii.chip),
                    child: Text(category, style: theme.textTheme.labelSmall?.copyWith(color: scheme.primary)),
                  ),
                const Spacer(),
                Icon(Icons.event_outlined, size: 14, color: scheme.onSurfaceVariant),
                Gap.w4,
                Text(
                  Fmt.date(date, bangla: bangla),
                  style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            Gap.h8,
            Text(note.titleFor(bangla: bangla), style: theme.textTheme.titleMedium),
            if (note.summaryFor(bangla: bangla).isNotEmpty) ...[
              Gap.h4,
              Text(
                note.summaryFor(bangla: bangla),
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (facts.isNotEmpty) ...[
              Gap.h12,
              Text(l.bookmarksKeyFacts, style: theme.textTheme.labelLarge),
              Gap.h4,
              for (final fact in visible)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.xxs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Icon(Icons.circle, size: 6, color: scheme.primary),
                      ),
                      Gap.w8,
                      Expanded(child: Text(fact, style: theme.textTheme.bodyMedium)),
                    ],
                  ),
                ),
              if (facts.length > _collapsedFacts)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    child: Text(
                      _expanded ? l.bookmarksShowLess : l.bookmarksShowMore(context.n(facts.length - _collapsedFacts)),
                    ),
                  ),
                ),
            ],
            if (note.links.isNotEmpty) ...[
              Gap.h8,
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.xs,
                children: [
                  for (final link in note.links.take(3))
                    ActionChip(
                      avatar: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: Text(link.title ?? l.bookmarksSourceLink, maxLines: 1, overflow: TextOverflow.ellipsis),
                      tooltip: link.url,
                      onPressed: () => unawaited(_open(link.url)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      // No browser available — nothing else to do.
    }
  }
}

/// Saved post → opens the full post.
class BookmarkPostTile extends StatelessWidget {
  const BookmarkPostTile({required this.bookmark, super.key});
  final Bookmark bookmark;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final post = BookmarkedPost.fromPayload(bookmark.payload);
    final name = post.displayName ?? l.bookmarksUnknownAuthor;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => unawaited(context.push(Routes.postDetail(bookmark.itemId))),
        child: Padding(
          padding: Gap.card,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        UserAvatar(name: name, url: post.authorAvatarUrl, radius: 14),
                        Gap.w8,
                        Expanded(
                          child: Text(
                            name,
                            style: theme.textTheme.labelLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    Gap.h8,
                    Text(
                      post.body.isEmpty ? l.bookmarksPostNoText : post.body,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Gap.h8,
                    Text(
                      Fmt.timeAgo(post.createdAt ?? bookmark.createdAt, bangla: context.isBn),
                      style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (post.imageUrl != null) ...[
                Gap.w12,
                AppNetworkImage(url: post.imageUrl!, width: 72, height: 72, borderRadius: Radii.button),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
