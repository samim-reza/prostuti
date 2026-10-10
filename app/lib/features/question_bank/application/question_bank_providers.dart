import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/pagination/paged_notifier.dart';
import 'package:prostuti/core/pagination/paged_state.dart';
import 'package:prostuti/features/question_bank/data/question_bank_models.dart';
import 'package:prostuti/features/question_bank/data/question_bank_repository.dart';

/// Every source with published questions.
final allSourcesProvider = FutureProvider.autoDispose<List<QuestionSource>>(
  (ref) => ref.watch(questionBankRepositoryProvider).sources(),
);

final sourceByIdProvider = Provider.autoDispose.family<QuestionSource?, int>((ref, id) {
  final list = ref.watch(allSourcesProvider).value;
  if (list == null) return null;
  for (final s in list) {
    if (s.id == id) return s;
  }
  return null;
});

/// Wrong-answer notebook for one subject filter (null = all subjects).
class WrongAnswersNotifier extends PagedNotifier<WrongAnswer, DateTime> {
  WrongAnswersNotifier(this.subjectId);

  final int? subjectId;

  @override
  Future<PageResult<WrongAnswer, DateTime>> fetchPage(DateTime? cursor) async {
    final page = await ref
        .read(questionBankRepositoryProvider)
        .wrongAnswersOrCached(before: cursor, subjectId: subjectId);
    return PageResult(page.items, page.nextCursor);
  }

  @override
  List<WrongAnswer>? readCachedFirstPage() => ref.read(questionBankRepositoryProvider).cachedWrongAnswers(subjectId);

  @override
  Object idOf(WrongAnswer item) => item.question.id;
}

final wrongAnswersProvider = NotifierProvider.autoDispose
    .family<WrongAnswersNotifier, PagedState<WrongAnswer, DateTime>, int?>(WrongAnswersNotifier.new);
