import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/bd_time.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:prostuti/features/home/application/home_helpers.dart';
import 'package:prostuti/features/onboarding/data/districts.dart';

String divisionLabel(BuildContext context, String division) {
  final l = context.l10n;
  return switch (division) {
    'dhaka' => l.onboardingDivisionDhaka,
    'chattogram' => l.onboardingDivisionChattogram,
    'rajshahi' => l.onboardingDivisionRajshahi,
    'khulna' => l.onboardingDivisionKhulna,
    'barishal' => l.onboardingDivisionBarishal,
    'sylhet' => l.onboardingDivisionSylhet,
    'rangpur' => l.onboardingDivisionRangpur,
    _ => l.onboardingDivisionMymensingh,
  };
}

/// Searchable list of all 64 districts (Bangla or English search).
Future<District?> showDistrictPicker(BuildContext context, {District? selected}) {
  return showModalBottomSheet<District>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _DistrictSheet(selected: selected),
  );
}

class _DistrictSheet extends StatefulWidget {
  const _DistrictSheet({this.selected});

  final District? selected;

  @override
  State<_DistrictSheet> createState() => _DistrictSheetState();
}

class _DistrictSheetState extends State<_DistrictSheet> {
  final _search = TextEditingController();
  List<District> _results = bangladeshDistricts;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _filter(String q) => setState(() => _results = bangladeshDistricts.where((d) => d.matches(q)).toList());

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final bangla = context.isBn;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.sm),
            child: TextField(
              controller: _search,
              autofocus: true,
              onChanged: _filter,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l.onboardingDistrictSearch,
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child: _results.isEmpty
                ? Center(child: Text(l.onboardingDistrictNone, style: theme.textTheme.bodyMedium))
                : ListView.builder(
                    controller: controller,
                    itemCount: _results.length,
                    itemExtent: 60,
                    itemBuilder: (context, i) {
                      final d = _results[i];
                      final selected = d == widget.selected;
                      return ListTile(
                        title: Text(d.name(bangla: bangla)),
                        subtitle: Text(
                          '${divisionLabel(context, d.division)} · ${d.name(bangla: !bangla)}',
                          style: theme.textTheme.bodySmall,
                        ),
                        selected: selected,
                        trailing: selected ? const Icon(Icons.check_rounded) : null,
                        onTap: () => Navigator.pop(context, d),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Selectable card for one exam schedule (title, date, tentative badge, days left).
class ScheduleOption extends StatelessWidget {
  const ScheduleOption({required this.schedule, required this.selected, required this.onTap, super.key});

  final ExamSchedule schedule;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final date = DateTime.utc(schedule.expectedDate.year, schedule.expectedDate.month, schedule.expectedDate.day);
    final days = daysUntil(date, BdTime.today());
    return Semantics(
      selected: selected,
      button: true,
      child: Card(
        color: selected ? scheme.primary.withValues(alpha: 0.07) : null,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.card,
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.6),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: Radii.card,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: selected ? scheme.primary : scheme.outline,
                ),
                Gap.w12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(schedule.title(context), style: theme.textTheme.titleSmall),
                      Gap.h4,
                      Wrap(
                        spacing: Gap.sm,
                        runSpacing: Gap.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            Fmt.date(date, bangla: context.isBn),
                            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          if (!schedule.isConfirmed)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 1),
                              decoration: BoxDecoration(
                                color: scheme.tertiary.withValues(alpha: 0.12),
                                borderRadius: Radii.chip,
                              ),
                              child: Text(
                                l.onboardingTentative,
                                style: theme.textTheme.labelSmall?.copyWith(color: scheme.tertiary),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Gap.w8,
                Column(
                  children: [
                    Text(context.n(days), style: theme.textTheme.titleMedium?.copyWith(color: scheme.primary)),
                    Text(l.onboardingDaysLeftShort, style: theme.textTheme.labelSmall),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
