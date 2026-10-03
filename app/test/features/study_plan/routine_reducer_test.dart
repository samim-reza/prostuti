import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/features/study_plan/application/plan_providers.dart';
import 'package:prostuti/features/study_plan/data/plan_models.dart';

PlanDay _day({
  PlanDayStatus status = PlanDayStatus.pending,
  int total = 3,
  List<bool> done = const [false, false, false],
}) => PlanDay(
  id: 11,
  date: DateTime.utc(2026, 10, 4),
  kind: PlanDayKind.study,
  titleBn: 'দিন',
  totalItems: total,
  status: status,
  items: [
    for (var i = 0; i < done.length; i++)
      PlanItem(key: 'k$i', type: PlanItemType.read, titleBn: 'কাজ $i', done: done[i]),
  ],
);

void main() {
  group('setItemDone', () {
    test('first item → partial', () {
      final next = setItemDone(_day(), 'k0');
      expect(next.items.first.done, isTrue);
      expect(next.completedItems, 1);
      expect(next.status, PlanDayStatus.partial);
    });

    test('last item → done', () {
      final next = setItemDone(_day(done: [true, true, false]), 'k2');
      expect(next.completedItems, 3);
      expect(next.status, PlanDayStatus.done);
      expect(next.progress, 1);
    });

    test('unknown or empty key / already done → same instance', () {
      final day = _day(done: [true, false, false]);
      expect(identical(setItemDone(day, 'nope'), day), isTrue);
      expect(identical(setItemDone(day, ''), day), isTrue);
      expect(identical(setItemDone(day, 'k0'), day), isTrue);
    });

    test('undo (revert of a failed optimistic update)', () {
      final ticked = setItemDone(_day(), 'k1');
      final reverted = setItemDone(ticked, 'k1', done: false);
      expect(reverted.completedItems, 0);
      expect(reverted.status, PlanDayStatus.pending);
    });

    test('a missed day stays missed when everything is unticked', () {
      final day = _day(status: PlanDayStatus.missed, done: [true, false, false]);
      expect(setItemDone(day, 'k0', done: false).status, PlanDayStatus.missed);
      expect(setItemDone(day, 'k1').status, PlanDayStatus.partial);
    });

    test('total_items from the server wins over the item count', () {
      final next = setItemDone(_day(total: 4, done: [true, true, false]), 'k2');
      expect(next.status, PlanDayStatus.partial, reason: '3 of 4 server-side items');
    });

    test('does not mutate the original', () {
      final day = _day();
      setItemDone(day, 'k0');
      expect(day.items.first.done, isFalse);
    });
  });

  group('applyPendingCompletions', () {
    test('re-applies queued offline check-offs for the same day only', () {
      final day = _day();
      final out = applyPendingCompletions(day, {
        PendingPlanItemsNotifier.keyOf(11, 'k1'),
        PendingPlanItemsNotifier.keyOf(12, 'k0'),
      });
      expect(out.items.map((i) => i.done), [false, true, false]);
      expect(out.status, PlanDayStatus.partial);
    });

    test('no pending → same instance', () {
      final day = _day();
      expect(identical(applyPendingCompletions(day, const {}), day), isTrue);
    });
  });
}
