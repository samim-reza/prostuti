import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/exam/application/exam_failure_messages.dart';
import 'package:prostuti/features/exam/application/question_bookmarks.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/exam/data/question_actions_repository.dart';

/// Bookmark toggle for a question (optimistic, works offline). [question]
/// should carry the answer/explanation when known — it becomes the payload.
class BookmarkQuestionButton extends ConsumerWidget {
  const BookmarkQuestionButton({required this.question, super.key});

  final Question question;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final saved = ref.watch(isQuestionBookmarkedProvider(question.id));
    return IconButton(
      tooltip: saved ? l.examBookmarkRemove : l.examBookmark,
      isSelected: saved,
      icon: const Icon(Icons.bookmark_border_rounded),
      selectedIcon: Icon(Icons.bookmark_rounded, color: Theme.of(context).colorScheme.primary),
      onPressed: () async {
        try {
          final r = await ref.read(questionBookmarksProvider.notifier).toggle(question);
          if (!context.mounted) return;
          showInfoSnack(
            context,
            r.queued ? l.examOfflineSaved : (r.bookmarked ? l.examBookmarked : l.examBookmarkRemoved),
          );
        } on Object catch (e) {
          if (context.mounted) showExamError(context, e);
        }
      },
    );
  }
}

/// "Report wrong answer" icon button.
class ReportQuestionButton extends StatelessWidget {
  const ReportQuestionButton({required this.questionId, super.key});

  final int questionId;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.l10n.examReportWrong,
      icon: const Icon(Icons.flag_outlined),
      onPressed: () => unawaited(showReportQuestionDialog(context, questionId)),
    );
  }
}

Future<void> showReportQuestionDialog(BuildContext context, int questionId) async {
  final details = await showDialog<String>(context: context, builder: (_) => const _ReportDialog());
  if (details == null || !context.mounted) return;
  final l = context.l10n;
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    final delivered = await container.read(questionActionsRepositoryProvider).report(questionId, details: details);
    if (context.mounted) showInfoSnack(context, delivered ? l.examReportThanks : l.examOfflineSaved);
  } on ConflictFailure {
    if (context.mounted) showInfoSnack(context, l.examReportDuplicate);
  } on Object catch (e) {
    if (context.mounted) showExamError(context, e);
  }
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog();

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      icon: const Icon(Icons.flag_rounded, color: AppColors.warning),
      title: Text(l.examReportWrong),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.examReportBody),
          Gap.h12,
          TextField(
            controller: _controller,
            maxLength: 1000,
            minLines: 2,
            maxLines: 5,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(hintText: l.examReportHint),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(l.examReportSend),
        ),
      ],
    );
  }
}
