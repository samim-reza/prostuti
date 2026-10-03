import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/paged_list_view.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/bookmarks/application/bookmarks_controller.dart';
import 'package:prostuti/features/bookmarks/data/bookmark.dart';
import 'package:prostuti/features/bookmarks/data/bookmarks_repository.dart';
import 'package:prostuti/features/bookmarks/presentation/widgets/bookmark_cards.dart';

/// Saved questions, notes and posts — each tab keyset-paginated, cached for
/// offline reading, with swipe-to-remove + undo.
class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return DefaultTabController(
      length: BookmarkType.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.bookmarksTitle),
          bottom: TabBar(
            tabs: [
              Tab(icon: const Icon(Icons.quiz_outlined), text: l.bookmarksTabQuestions),
              Tab(icon: const Icon(Icons.article_outlined), text: l.bookmarksTabNotes),
              Tab(icon: const Icon(Icons.forum_outlined), text: l.bookmarksTabPosts),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _BookmarkTab(type: BookmarkType.question),
            _BookmarkTab(type: BookmarkType.note),
            _BookmarkTab(type: BookmarkType.post),
          ],
        ),
      ),
    );
  }
}

class _BookmarkTab extends ConsumerStatefulWidget {
  const _BookmarkTab({required this.type});
  final BookmarkType type;

  @override
  ConsumerState<_BookmarkTab> createState() => _BookmarkTabState();
}

class _BookmarkTabState extends ConsumerState<_BookmarkTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Future<void> _remove(Bookmark b) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(bookmarksProvider(widget.type).notifier);
    final repo = ref.read(bookmarksRepositoryProvider);
    try {
      final result = await notifier.remove(b);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(result.synced ? l.bookmarksRemoved : '${l.bookmarksRemoved} · ${l.offlineSaved}'),
            action: SnackBarAction(
              label: l.bookmarksUndo,
              onPressed: () => unawaited(_undo(notifier, repo, b, result.index)),
            ),
          ),
        );
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _undo(BookmarksNotifier notifier, BookmarksRepository repo, Bookmark b, int index) async {
    try {
      // The tab may be gone (screen closed) — then just restore the row.
      if (mounted) {
        await notifier.restore(b, index);
      } else {
        await repo.restore(b);
      }
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = context.l10n;
    final type = widget.type;
    final state = ref.watch(bookmarksProvider(type));
    final notifier = ref.read(bookmarksProvider(type).notifier);
    final (icon, title, hint) = switch (type) {
      BookmarkType.question => (Icons.quiz_outlined, l.bookmarksEmptyQuestions, l.bookmarksEmptyQuestionsHint),
      BookmarkType.note => (Icons.article_outlined, l.bookmarksEmptyNotes, l.bookmarksEmptyNotesHint),
      BookmarkType.post => (Icons.forum_outlined, l.bookmarksEmptyPosts, l.bookmarksEmptyPostsHint),
    };

    return PagedListView<Bookmark>(
      state: state,
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.lg),
      separator: Gap.h12,
      loading: const SkeletonCards(height: 160),
      onLoadMore: () => unawaited(notifier.loadMore()),
      onRefresh: notifier.refresh,
      onRetry: () => unawaited(notifier.retry()),
      empty: EmptyView(icon: icon, title: title, message: hint),
      itemBuilder: (context, b, _) => Dismissible(
        key: ValueKey(b.key),
        direction: DismissDirection.endToStart,
        background: const _DismissBackground(),
        onDismissed: (_) => unawaited(_remove(b)),
        child: switch (b.type) {
          BookmarkType.question => BookmarkQuestionCard(bookmark: b),
          BookmarkType.note => BookmarkNoteCard(bookmark: b),
          BookmarkType.post => BookmarkPostTile(bookmark: b),
        },
      ),
    );
  }
}

class _DismissBackground extends StatelessWidget {
  const _DismissBackground();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: Radii.card),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(context.l10n.bookmarksRemove, style: TextStyle(color: scheme.onErrorContainer)),
          Gap.w8,
          Icon(Icons.bookmark_remove_rounded, color: scheme.onErrorContainer),
        ],
      ),
    );
  }
}
