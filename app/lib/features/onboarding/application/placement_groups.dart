import 'package:flutter/foundation.dart';
import 'package:prostuti/features/study_plan/data/readiness_models.dart';

/// The four placement groups of the level test (mirrors `subjects.placement_group`).
enum PlacementGroup { bangla, english, math, gk }

/// Subject code → placement group (everything else is general knowledge).
PlacementGroup placementGroupOf(String subjectCode) => switch (subjectCode) {
  'bangla' => PlacementGroup.bangla,
  'english' => PlacementGroup.english,
  'math' || 'mental_ability' => PlacementGroup.math,
  _ => PlacementGroup.gk,
};

@immutable
class GroupLevel {
  const GroupLevel({required this.group, required this.level, required this.scorePct});

  final PlacementGroup group;
  final SkillLevel level;

  /// 0…1.
  final double scorePct;
}

/// Collapses per-subject levels (every subject of a group gets the group's
/// placement score) into one row per group, in test order. Pure; tested.
List<GroupLevel> groupLevels(Readiness readiness) {
  final codes = {for (final s in readiness.subjects) s.subjectId: s.code};
  final byGroup = <PlacementGroup, List<SubjectLevel>>{};
  for (final lv in readiness.levels) {
    final code = codes[lv.subjectId];
    if (code == null) continue;
    byGroup.putIfAbsent(placementGroupOf(code), () => []).add(lv);
  }
  final out = <GroupLevel>[];
  for (final g in PlacementGroup.values) {
    final list = byGroup[g];
    if (list == null || list.isEmpty) continue;
    final avg = list.fold<double>(0, (sum, lv) => sum + lv.scorePct) / list.length;
    // Every subject of a group shares the server's level; trust it.
    out.add(GroupLevel(group: g, level: list.first.level, scorePct: avg));
  }
  return out;
}
