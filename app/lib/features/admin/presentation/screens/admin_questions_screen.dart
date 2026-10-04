import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/paged_list_view.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/admin/application/admin_controllers.dart';
import 'package:prostuti/features/admin/data/admin_models.dart';
import 'package:prostuti/features/admin/presentation/widgets/admin_common.dart';
import 'package:prostuti/features/admin/presentation/widgets/question_editor_page.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:url_launcher/url_launcher.dart';

/// Review queue for the question bank (AI-generated and imported questions).
class AdminQuestionsScreen extends ConsumerStatefulWidget {
  const AdminQuestionsScreen({super.key});

  @override
  ConsumerState<AdminQuestionsScreen> createState() => _AdminQuestionsScreenState();
}

class _AdminQuestionsScreenState extends ConsumerState<AdminQuestionsScreen> {
  /// Opens on the tab the link asks for (the dashboard's "Flagged" card adds
  /// `?review=flagged`), unverified otherwise.
  late ReviewStatus _review = ReviewStatus.parse(GoRouterState.of(context).uri.queryParameters['review']);
  int? _subjectId;

  QuestionFilter get _filter => (review: _review, subjectId: _subjectId);

  String _reviewLabel(AppLocalizations l, ReviewStatus r) => switch (r) {
    ReviewStatus.unverified => l.adminReviewUnverified,
    ReviewStatus.flagged => l.adminReviewFlagged,
    ReviewStatus.verified => l.adminReviewVerified,
  };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final subjects = ref.watch(subjectsProvider).value ?? const <Subject>[];
    final filter = _filter;
    final state = ref.watch(adminQuestionsProvider(filter));
    final notifier = ref.read(adminQuestionsProvider(filter).notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.adminQuestionsTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.sm),
              children: [
                for (final r in ReviewStatus.values) ...[
                  ChoiceChip(
                    label: Text(_reviewLabel(l, r)),
                    selected: _review == r,
                    onSelected: (_) => setState(() => _review = r),
                  ),
                  Gap.w8,
                ],
                _SubjectFilter(
                  subjects: subjects,
                  selected: _subjectId,
                  onChanged: (id) => setState(() => _subjectId = id),
                ),
              ],
            ),
          ),
        ),
      ),
      body: isOfflineFirstPageError(state)
          ? AdminErrorView(error: state.error!, onRetry: () => unawaited(notifier.refresh()))
          : PagedListView<AdminQuestion>(
              state: state,
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.lg),
              separator: Gap.h12,
              loading: const SkeletonCards(height: 240),
              onLoadMore: () => unawaited(notifier.loadMore()),
              onRefresh: notifier.refresh,
              onRetry: () => unawaited(notifier.retry()),
              empty: EmptyView(
                icon: Icons.task_alt_rounded,
                title: l.adminQuestionsEmpty,
                message: l.adminQuestionsEmptyHint,
              ),
              itemBuilder: (context, q, _) => _QuestionCard(
                question: q,
                subject: _subjectFor(subjects, q.subjectId),
                onAction: (patch) => unawaited(_apply(notifier, q, patch)),
                onEdit: () => unawaited(_edit(notifier, q)),
                onReject: () => unawaited(_reject(notifier, q)),
              ),
            ),
    );
  }

  static Subject? _subjectFor(List<Subject> subjects, int id) {
    for (final s in subjects) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> _apply(AdminQuestionsNotifier notifier, AdminQuestion q, Map<String, dynamic> patch) async {
    final l = context.l10n;
    if (!ensureOnline(context)) return;
    try {
      await notifier.apply(q, patch);
      if (mounted) showInfoSnack(context, l.adminQuestionUpdated(context.n(q.id)));
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _reject(AdminQuestionsNotifier notifier, AdminQuestion q) async {
    final l = context.l10n;
    final ok = await confirmDialog(
      context,
      title: l.adminRejectTitle,
      message: l.adminRejectBody,
      confirmLabel: l.adminReject,
      destructive: true,
    );
    if (ok && mounted) await _apply(notifier, q, const {'status': 'rejected'});
  }

  Future<void> _edit(AdminQuestionsNotifier notifier, AdminQuestion q) async {
    final edit = await QuestionEditorPage.open(context, q);
    if (edit == null || !mounted) return;
    final patch = buildQuestionPatch(q, edit);
    if (patch.isEmpty) {
      showInfoSnack(context, context.l10n.adminNoChanges);
      return;
    }
    await _apply(notifier, q, patch);
  }
}

class _SubjectFilter extends StatelessWidget {
  const _SubjectFilter({required this.subjects, required this.selected, required this.onChanged});

  final List<Subject> subjects;
  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    String? name;
    for (final s in subjects) {
      if (s.id == selected) name = s.name(context);
    }
    return PopupMenuButton<int>(
      tooltip: l.adminFilterSubject,
      onSelected: (id) => onChanged(id < 0 ? null : id),
      itemBuilder: (context) => [
        PopupMenuItem(value: -1, child: Text(l.adminAllSubjects)),
        for (final s in subjects) PopupMenuItem(value: s.id, child: Text(s.name(context))),
      ],
      child: Chip(avatar: const Icon(Icons.filter_list_rounded, size: 18), label: Text(name ?? l.adminAllSubjects)),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.question,
    required this.subject,
    required this.onAction,
    required this.onEdit,
    required this.onReject,
  });

  final AdminQuestion question;
  final Subject? subject;
  final ValueChanged<Map<String, dynamic>> onAction;
  final VoidCallback onEdit;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final q = question;
    final (reviewLabel, reviewColor) = switch (q.reviewStatus) {
      ReviewStatus.unverified => (l.adminReviewUnverified, AppColors.warning),
      ReviewStatus.flagged => (l.adminReviewFlagged, AppColors.danger),
      ReviewStatus.verified => (l.adminReviewVerified, AppColors.success),
    };
    final source = [if (q.sourceRef != null) q.sourceRef!, if (q.year != null) context.n(q.year!)].join(' · ');

    return Card(
      child: Padding(
        padding: Gap.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('#${context.n(q.id)}', style: theme.textTheme.labelLarge),
                if (subject != null) AdminTag(label: subject!.name(context), color: subject!.color),
                AdminTag(label: reviewLabel, color: reviewColor),
                if (q.isAiGenerated)
                  AdminTag(label: l.adminAiGenerated, color: const Color(0xFF7A4BD6), icon: Icons.auto_awesome),
                if (q.status != 'published')
                  AdminTag(
                    label: switch (q.status) {
                      'draft' => l.adminStatusDraft,
                      'archived' => l.adminStatusArchived,
                      _ => q.status,
                    },
                    color: scheme.outline,
                  ),
              ],
            ),
            Gap.h12,
            SelectableText(q.stem, style: theme.textTheme.titleSmall),
            Gap.h8,
            for (var i = 0; i < q.options.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.xxs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      i == q.correctIndex ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      size: 20,
                      color: i == q.correctIndex ? AppColors.success : scheme.outline,
                    ),
                    Gap.w8,
                    Expanded(
                      child: Text(
                        q.options[i],
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: i == q.correctIndex ? FontWeight.w700 : null,
                          color: i == q.correctIndex ? AppColors.success : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (q.explanation?.trim().isNotEmpty ?? false) ...[
              Gap.h8,
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Gap.md),
                decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.07), borderRadius: Radii.button),
                child: Text(q.explanation!, style: theme.textTheme.bodySmall),
              ),
            ],
            if (source.isNotEmpty || q.sourceUrl != null) ...[
              Gap.h8,
              InkWell(
                onTap: q.sourceUrl == null ? null : () => unawaited(_open(q.sourceUrl!)),
                child: Row(
                  children: [
                    Icon(Icons.source_outlined, size: 16, color: scheme.onSurfaceVariant),
                    Gap.w4,
                    Expanded(
                      child: Text(
                        l.adminSource(source.isEmpty ? (q.sourceUrl ?? '') : source),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: q.sourceUrl == null ? scheme.onSurfaceVariant : scheme.primary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Gap.h8,
            const Divider(),
            Wrap(
              spacing: Gap.xs,
              children: [
                if (q.reviewStatus != ReviewStatus.verified)
                  TextButton.icon(
                    onPressed: () => onAction(const {'review_status': 'verified'}),
                    icon: const Icon(Icons.verified_outlined),
                    label: Text(l.adminVerify),
                  ),
                if (q.reviewStatus != ReviewStatus.flagged)
                  TextButton.icon(
                    onPressed: () => onAction(const {'review_status': 'flagged'}),
                    icon: const Icon(Icons.flag_outlined),
                    label: Text(l.adminFlag),
                  ),
                TextButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit_outlined), label: Text(l.edit)),
                TextButton.icon(
                  onPressed: onReject,
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                  icon: const Icon(Icons.block_rounded),
                  label: Text(l.adminReject),
                ),
              ],
            ),
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
      // ignore: no browser
    }
  }
}
