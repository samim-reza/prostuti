import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/features/study_plan/data/readiness_models.dart';

/// Short axis labels for the radar chart (full names are too long).
String subjectShortName(BuildContext context, SubjectReadiness s) {
  final l = context.l10n;
  return switch (s.code) {
    'bangla' => l.studyPlanShortBangla,
    'english' => l.studyPlanShortEnglish,
    'bd_affairs' => l.studyPlanShortBdAffairs,
    'international' => l.studyPlanShortInternational,
    'geography' => l.studyPlanShortGeography,
    'science' => l.studyPlanShortScience,
    'computer' => l.studyPlanShortComputer,
    'math' => l.studyPlanShortMath,
    'mental_ability' => l.studyPlanShortMental,
    'ethics' => l.studyPlanShortEthics,
    _ => (context.isBn ? s.nameBn : s.nameEn).split(RegExp('[ ,]')).first,
  };
}

/// Single-series radar of subject mastery (0–100). Needs ≥ 3 subjects.
class MasteryRadarChart extends StatelessWidget {
  const MasteryRadarChart({required this.subjects, super.key});

  final List<SubjectReadiness> subjects;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = scheme.primary;
    return AspectRatio(
      aspectRatio: 1.15,
      child: Semantics(
        label: subjects.map((s) => '${subjectShortName(context, s)} ${context.n(s.mastery)}%').join(', '),
        child: ExcludeSemantics(
          child: RadarChart(
            RadarChartData(
              dataSets: [
                RadarDataSet(
                  dataEntries: [for (final s in subjects) RadarEntry(value: s.mastery.toDouble())],
                  fillColor: color.withValues(alpha: 0.18),
                  borderColor: color,
                  borderWidth: 2,
                  entryRadius: 3,
                ),
                // Invisible 0–100 frame so the scale is absolute, not relative.
                RadarDataSet(
                  dataEntries: [for (final _ in subjects) const RadarEntry(value: 100)],
                  fillColor: Colors.transparent,
                  borderColor: Colors.transparent,
                  borderWidth: 0,
                  entryRadius: 0,
                ),
              ],
              radarShape: RadarShape.polygon,
              radarBackgroundColor: Colors.transparent,
              radarBorderData: BorderSide(color: scheme.outlineVariant),
              gridBorderData: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
              tickBorderData: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
              tickCount: 4,
              ticksTextStyle: const TextStyle(color: Colors.transparent, fontSize: 1),
              titlePositionPercentageOffset: 0.14,
              titleTextStyle: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              getTitle: (index, angle) => RadarChartTitle(text: subjectShortName(context, subjects[index])),
              radarTouchData: RadarTouchData(enabled: false),
            ),
          ),
        ),
      ),
    );
  }
}

/// Readiness over time (one series → no legend; the card title names it).
class ReadinessHistoryChart extends StatelessWidget {
  const ReadinessHistoryChart({required this.history, super.key});

  final List<ReadinessPoint> history;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);
    final spots = [for (final (i, p) in history.indexed) FlSpot(i.toDouble(), p.readiness.toDouble())];
    final maxY = math.min(100, ((history.map((p) => p.readiness).reduce(math.max) + 10) / 10).ceil() * 10).toDouble();
    final step = math.max(1, (history.length / 4).ceil());
    String dateLabel(int i) => '${context.n(history[i].date.day)}/${context.n(history[i].date.month)}';

    return AspectRatio(
      aspectRatio: 1.7,
      child: Padding(
        padding: const EdgeInsets.only(right: Gap.sm, top: Gap.sm),
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: maxY,
            minX: 0,
            maxX: (history.length - 1).toDouble(),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: maxY / 4,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: scheme.outlineVariant.withValues(alpha: 0.5), strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 36,
                  interval: maxY / 4,
                  getTitlesWidget: (value, meta) => SideTitleWidget(
                    meta: meta,
                    child: Text('${context.n(value.round())}%', style: label),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  interval: 1,
                  getTitlesWidget: (value, meta) {
                    final i = value.round();
                    if (i < 0 || i >= history.length || value != i.toDouble()) return const SizedBox.shrink();
                    if (i % step != 0 && i != history.length - 1) return const SizedBox.shrink();
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(dateLabel(i), style: label),
                    );
                  },
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => scheme.inverseSurface,
                getTooltipItems: (spots) => [
                  for (final s in spots)
                    LineTooltipItem(
                      '${dateLabel(s.x.round())}\n${context.n(s.y.round())}%',
                      TextStyle(color: scheme.onInverseSurface, fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                preventCurveOverShooting: true,
                color: scheme.primary,
                dotData: FlDotData(show: history.length <= 12),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [scheme.primary.withValues(alpha: 0.22), scheme.primary.withValues(alpha: 0)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
