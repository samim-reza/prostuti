import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/pagination/paged_state.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';

/// Infinite, lazily built list bound to a [PagedState].
///
/// * builds only visible rows (`ListView.builder`/slivers);
/// * prefetches the next page when the user is within [prefetchExtent]
///   pixels of the end, so scrolling never hits a spinner on fast networks;
/// * pull-to-refresh, empty, error and "load more failed" states included.
class PagedListView<T> extends StatefulWidget {
  const PagedListView({
    required this.state,
    required this.itemBuilder,
    required this.onLoadMore,
    required this.onRefresh,
    this.onRetry,
    this.separator,
    this.padding = const EdgeInsets.symmetric(vertical: Gap.sm),
    this.header,
    this.empty,
    this.loading,
    this.reverse = false,
    this.prefetchExtent = 600,
    this.controller,
    super.key,
  });

  final PagedState<T, Object?> state;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final VoidCallback onLoadMore;
  final Future<void> Function() onRefresh;
  final VoidCallback? onRetry;
  final Widget? separator;
  final EdgeInsets padding;
  final Widget? header;
  final Widget? empty;
  final Widget? loading;
  final bool reverse;
  final double prefetchExtent;
  final ScrollController? controller;

  @override
  State<PagedListView<T>> createState() => _PagedListViewState<T>();
}

class _PagedListViewState<T> extends State<PagedListView<T>> {
  bool _onScroll(ScrollNotification n) {
    if (n.metrics.extentAfter < widget.prefetchExtent && widget.state.hasMore && !widget.state.isLoadingMore) {
      widget.onLoadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    if (s.isLoadingFirst && s.items.isEmpty) return widget.loading ?? const SkeletonList();
    if (s.error != null && s.items.isEmpty) {
      return RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView(
          children: [
            if (widget.header != null) widget.header!,
            ErrorView(error: s.error!, onRetry: widget.onRetry ?? widget.onRefresh),
          ],
        ),
      );
    }
    if (s.isEmpty) {
      return RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView(children: [if (widget.header != null) widget.header!, widget.empty ?? const EmptyView()]),
      );
    }

    final hasHeader = widget.header != null;
    final footerCount = (s.isLoadingMore || (s.error != null) || !s.hasMore) ? 1 : 0;
    final count = s.items.length + (hasHeader ? 1 : 0) + footerCount;

    Widget list = ListView.separated(
      controller: widget.controller,
      reverse: widget.reverse,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: widget.padding,
      itemCount: count,
      separatorBuilder: (_, i) {
        final itemIndex = i - (hasHeader ? 1 : 0);
        if (itemIndex < 0 || itemIndex >= s.items.length - 1) return const SizedBox.shrink();
        return widget.separator ?? const SizedBox.shrink();
      },
      itemBuilder: (context, i) {
        if (hasHeader && i == 0) return widget.header!;
        final itemIndex = i - (hasHeader ? 1 : 0);
        if (itemIndex < s.items.length) return widget.itemBuilder(context, s.items[itemIndex], itemIndex);
        return _Footer(state: s, onRetry: widget.onRetry ?? widget.onLoadMore);
      },
    );
    list = NotificationListener<ScrollNotification>(onNotification: _onScroll, child: list);
    if (widget.reverse) return list;
    return RefreshIndicator(onRefresh: widget.onRefresh, child: list);
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.state, required this.onRetry});
  final PagedState<Object?, Object?> state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(Gap.lg),
        child: Center(child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4))),
      );
    }
    if (state.error != null) {
      return Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Center(
          child: TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(context.l10n.retry)),
        ),
      );
    }
    return const SizedBox(height: Gap.xl);
  }
}
