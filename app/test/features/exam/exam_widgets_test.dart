// ignore_for_file: cascade_invocations
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:prostuti/features/exam/application/exam_session_controller.dart';
import 'package:prostuti/features/exam/data/exam_models.dart';
import 'package:prostuti/features/exam/data/exam_repository.dart';
import 'package:prostuti/features/exam/presentation/widgets/exam_session_widgets.dart';
import 'package:prostuti/features/exam/presentation/widgets/option_tile.dart';

import 'fixtures.dart';

class _MockRepo extends Mock implements ExamRepository;

Widget _app(Widget child, {List<Override> overrides = const [], Locale locale = const Locale('bn')}) => ProviderScope(
  overrides: overrides,
  retry: (_, _) => null,
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  testWidgets('OptionTile shows the verdict icons and handles taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            OptionTile(label: 'ক', text: 'সঠিক', visual: OptionVisual.correct, onTap: () => taps++),
            const OptionTile(label: 'খ', text: 'ভুল', visual: OptionVisual.wrong),
          ],
        ),
      ),
    );
    expect(find.text('ক'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
    await tester.tap(find.text('সঠিক'));
    expect(taps, 1);
  });

  testWidgets('ExamTimerChip renders Bangla digits', (tester) async {
    final remaining = ValueNotifier(const Duration(minutes: 4, seconds: 5));
    addTearDown(remaining.dispose);
    await tester.pumpWidget(_app(ExamTimerChip(remaining: remaining)));
    expect(find.text('০৪:০৫'), findsOneWidget);
    remaining.value = const Duration(seconds: 59);
    await tester.pump();
    expect(find.text('০০:৫৯'), findsOneWidget);
  });

  testWidgets('ExamQuestionCard: bubbles select, change and clear; source is shown', (tester) async {
    final repo = _MockRepo();
    when(() => repo.loadSession('s1')).thenAnswer((_) async => session());
    when(() => repo.savedAnswers('s1')).thenReturn({});
    when(() => repo.savedFlags('s1')).thenReturn({});
    when(() => repo.isSubmissionPending('s1')).thenReturn(false);
    when(() => repo.saveAnswers(any(), any())).thenAnswer((_) async {});
    when(() => repo.saveFlags(any(), any())).thenAnswer((_) async {});
    final q = Question.fromJson(questionJson(101));

    await tester.pumpWidget(
      _app(
        ExamQuestionCard(sessionId: 's1', question: q, number: 1),
        overrides: [
          examRepositoryProvider.overrideWithValue(repo),
          subjectsProvider.overrideWith((ref) async => const <Subject>[]),
        ],
      ),
    );
    final element = tester.element(find.byType(ExamQuestionCard));
    final container = ProviderScope.containerOf(element);
    container.listen(examSessionControllerProvider('s1'), (_, _) {});
    await tester.pumpAndSettle();

    // Bangla labels and the source ("where it came from").
    for (final label in ['ক', 'খ', 'গ', 'ঘ']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.textContaining('প্রস্তুতি কিউরেটেড প্রশ্নব্যাংক'), findsOneWidget);

    int? selected() => container.read(examSessionControllerProvider('s1')).value!.sheet.selectedFor(101);
    await tester.tap(find.text('খ উত্তর'));
    await tester.pump();
    expect(selected(), 1);
    await tester.tap(find.text('ঘ উত্তর'));
    await tester.pump();
    expect(selected(), 3);
    await tester.tap(find.text('ঘ উত্তর'));
    await tester.pump();
    expect(selected(), isNull);

    await tester.tap(find.byTooltip('পরে দেখার জন্য চিহ্নিত করুন'));
    await tester.pump();
    expect(container.read(examSessionControllerProvider('s1')).value!.sheet.isFlagged(101), isTrue);
    await tester.pump(const Duration(milliseconds: 400)); // flush the debounced save
  });
}
