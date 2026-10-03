import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/entitlements/feature_access.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/daily_notes/application/current_affairs_failures.dart';
import 'package:prostuti/features/daily_notes/application/today_notes_controller.dart';
import 'package:prostuti/features/daily_notes/data/daily_note.dart';
import 'package:prostuti/features/daily_notes/presentation/notes_download_flow.dart';
import 'package:prostuti/features/daily_notes/presentation/screens/downloaded_notes_screen.dart';
import 'package:prostuti/features/daily_notes/presentation/widgets/note_card.dart';
import 'package:prostuti/features/daily_notes/presentation/widgets/notes_sections.dart';

/// Today's current-affairs notes (visible on their own Bangladesh day only),
/// with category filters, bookmarks, PDF download and the daily-exam CTA.
class DailyNotesScreen extends ConsumerStatefulWidget {
  const DailyNotesScreen({super.key});

  @override
  ConsumerState<DailyNotesScreen> createState() => _DailyNotesScreenState();
}

class _DailyNotesScreenState extends ConsumerState<DailyNotesScreen> {
  final _busy = ValueNotifier<String?>(null);
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    registerCurrentAffairsMessages();
    // Warm up the rewarded ad so it shows instantly on "Download".
    unawaited(preloadNotesAd(ref));
  }

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final hadData = ref.read(todayNotesProvider).hasValue;
    final error = await ref.read(todayNotesProvider.notifier).refresh();
    if (error != null && hadData && mounted) showErrorSnack(context, error);
  }

  void _onDayEnded() {
    ref.read(noteCategoryFilterProvider.notifier).select(null);
    unawaited(_refresh());
  }

  Future<void> _download(TodayNotes today) async {
    if (_downloading) return; // ignore rapid repeat taps
    _downloading = true;
    try {
      await downloadTodayNotesPdf(
        context: context,
        ref: ref,
        today: today,
        onBusy: (message) {
          if (mounted) _busy.value = message;
        },
      );
    } finally {
      _downloading = false;
    }
  }

  Future<void> _toggleBookmark(DailyNote note) async {
    final l = context.l10n;
    try {
      final result = await ref.read(noteBookmarksProvider.notifier).toggle(note);
      if (result == null || !mounted) return;
      final message = result.bookmarked ? l.dailyNotesBookmarked : l.dailyNotesUnbookmarked;
      showInfoSnack(context, result.queued ? '$message · ${l.offlineSaved}' : message);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  void _openDownloads() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DownloadedNotesScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(todayNotesProvider);
    final today = async.value;
    final hasNotes = today?.notes.isNotEmpty ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.dailyNotesTitle),
        actions: [
          if (!kIsWeb)
            IconButton(
              onPressed: _openDownloads,
              tooltip: l.dailyNotesDownloadedNotes,
              icon: const Icon(Icons.folder_open_rounded),
            ),
          if (hasNotes)
            IconButton(
              onPressed: () => _download(today!),
              tooltip: l.dailyNotesDownloadPdf,
              icon: const Icon(Icons.download_rounded),
            ),
          Gap.w4,
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _refresh,
            child: switch (async) {
              AsyncValue(:final value?) =>
                value.notes.isEmpty
                    ? _EmptyNotes(today: value, onRefresh: _refresh)
                    : _NotesList(
                        today: value,
                        onDayEnded: _onDayEnded,
                        onDownload: () => _download(value),
                        onToggleBookmark: _toggleBookmark,
                      ),
              AsyncValue(:final error?) => _Scrollable(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ErrorView(error: error, onRetry: () => ref.invalidate(todayNotesProvider)),
                    // Saved PDFs work offline — keep them one tap away.
                    if (!kIsWeb)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(200, 44)),
                        onPressed: _openDownloads,
                        icon: const Icon(Icons.folder_open_rounded),
                        label: Text(l.dailyNotesDownloadedNotes),
                      ),
                  ],
                ),
              ),
              _ => const _NotesSkeleton(),
            },
          ),
          ValueListenableBuilder<String?>(
            valueListenable: _busy,
            builder: (_, message, _) => message == null ? const SizedBox.shrink() : BusyOverlay(message: message),
          ),
        ],
      ),
    );
  }
}

class _NotesList extends ConsumerWidget {
  const _NotesList({
    required this.today,
    required this.onDayEnded,
    required this.onDownload,
    required this.onToggleBookmark,
  });

  final TodayNotes today;
  final VoidCallback onDayEnded;
  final VoidCallback onDownload;
  final ValueChanged<DailyNote> onToggleBookmark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = today.categoryCounts;
    var selected = ref.watch(noteCategoryFilterProvider);
    if (selected != null && !counts.containsKey(selected)) selected = null;
    final notes = today.filtered(selected);
    final exam = today.dailyExam;
    final adFree = ref.watch(hasFeatureProvider(Features.adFree));

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: NotesHeader(today: today, onDayEnded: onDayEnded),
        ),
        if (exam != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 0),
            sliver: SliverToBoxAdapter(child: DailyExamCtaCard(exam: exam)),
          ),
        const SliverToBoxAdapter(child: Gap.h4),
        SliverPersistentHeader(
          pinned: true,
          delegate: CategoryFilterBarDelegate(
            counts: counts,
            total: today.notes.length,
            selected: selected,
            onSelected: ref.read(noteCategoryFilterProvider.notifier).select,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, 0),
          sliver: SliverList.separated(
            itemCount: notes.length,
            separatorBuilder: (_, _) => Gap.h12,
            itemBuilder: (context, i) =>
                _BookmarkAwareNoteCard(key: ValueKey(notes[i].id), note: notes[i], onToggleBookmark: onToggleBookmark),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.xxl),
          sliver: SliverToBoxAdapter(
            child: NotesDownloadCard(
              downloaded: today.downloaded,
              needsAd: !adFree && !today.downloaded,
              onDownload: onDownload,
            ),
          ),
        ),
      ],
    );
  }
}

/// Rebuilds only when *this* note's bookmark state changes.
class _BookmarkAwareNoteCard extends ConsumerWidget {
  const _BookmarkAwareNoteCard({required this.note, required this.onToggleBookmark, super.key});

  final DailyNote note;
  final ValueChanged<DailyNote> onToggleBookmark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (bookmarked, pending) = ref.watch(
      noteBookmarksProvider.select((s) => (s.value?.contains(note.id) ?? false, s.value?.isPending(note.id) ?? false)),
    );
    return NoteCard(
      note: note,
      bookmarked: bookmarked,
      bookmarkPending: pending,
      onToggleBookmark: () => onToggleBookmark(note),
    );
  }
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes({required this.today, required this.onRefresh});

  final TodayNotes today;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final exam = today.dailyExam;
    return _Scrollable(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          EmptyView(
            icon: Icons.hourglass_top_rounded,
            title: l.dailyNotesEmptyTitle,
            message: l.dailyNotesEmptyBody,
            action: () => unawaited(onRefresh()),
            actionLabel: l.dailyNotesRefresh,
          ),
          if (exam != null)
            Padding(
              padding: Gap.screen,
              child: DailyExamCtaCard(exam: exam),
            ),
        ],
      ),
    );
  }
}

/// Full-height scrollable so pull-to-refresh works on empty/error states.
class _Scrollable extends StatelessWidget {
  const _Scrollable({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _NotesSkeleton extends StatelessWidget {
  const _NotesSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      physics: AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonShimmer(
            child: Padding(
              padding: EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 220, height: 22),
                  Gap.h8,
                  SkeletonBox(width: 280, height: 12),
                  Gap.h16,
                  SkeletonBox(height: 52, radius: 12),
                  Gap.h16,
                  Row(
                    children: [
                      SkeletonBox(width: 72, height: 32, radius: 16),
                      Gap.w8,
                      SkeletonBox(width: 96, height: 32, radius: 16),
                      Gap.w8,
                      SkeletonBox(width: 84, height: 32, radius: 16),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SkeletonCards(height: 220),
        ],
      ),
    );
  }
}
