import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/admin/data/admin_models.dart';
import 'package:prostuti/features/profile/application/profile_edit.dart';

/// Create / edit an exam schedule. Pops with the edited [AdminSchedule].
class ScheduleEditorPage extends ConsumerStatefulWidget {
  const ScheduleEditorPage({this.initial, super.key});
  final AdminSchedule? initial;

  static Future<AdminSchedule?> open(BuildContext context, {AdminSchedule? initial}) => Navigator.of(context).push(
    MaterialPageRoute<AdminSchedule>(fullscreenDialog: true, builder: (_) => ScheduleEditorPage(initial: initial)),
  );

  @override
  ConsumerState<ScheduleEditorPage> createState() => _ScheduleEditorPageState();
}

class _ScheduleEditorPageState extends ConsumerState<ScheduleEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleBn;
  late final TextEditingController _titleEn;
  late final TextEditingController _stage;
  late final TextEditingController _sourceUrl;
  late final TextEditingController _notes;
  late String _examType;
  late DateTime _date;
  late bool _confirmed;
  late bool _active;

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    _titleBn = TextEditingController(text: s?.titleBn ?? '');
    _titleEn = TextEditingController(text: s?.titleEn ?? '');
    _stage = TextEditingController(text: s?.stage ?? 'preliminary');
    _sourceUrl = TextEditingController(text: s?.sourceUrl ?? '');
    _notes = TextEditingController(text: s?.notes ?? '');
    _examType = s?.examType ?? 'bcs';
    _date = s?.expectedDate ?? DateTime.now().add(const Duration(days: 90));
    _confirmed = s?.isConfirmed ?? false;
    _active = s?.isActive ?? true;
  }

  @override
  void dispose() {
    _titleBn.dispose();
    _titleEn.dispose();
    _stage.dispose();
    _sourceUrl.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _dateChanged => widget.initial != null && !_build().sameDateAs(widget.initial!);

  AdminSchedule _build() => AdminSchedule(
    id: widget.initial?.id,
    examType: _examType,
    titleBn: _titleBn.text,
    titleEn: _titleEn.text,
    stage: _stage.text,
    expectedDate: DateTime(_date.year, _date.month, _date.day),
    isConfirmed: _confirmed,
    sourceUrl: _sourceUrl.text,
    notes: _notes.text,
    isActive: _active,
  );

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = DateTime(now.year - 1);
    final last = DateTime(now.year + 5);
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      // An old schedule can sit outside the usual window; the picker asserts
      // that the initial date is inside it.
      firstDate: _date.isBefore(first) ? _date : first,
      lastDate: _date.isAfter(last) ? _date : last,
      helpText: context.l10n.adminScheduleDate,
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    final l = context.l10n;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_dateChanged) {
      final ok = await confirmDialog(
        context,
        title: l.adminScheduleReplanTitle,
        message: l.adminScheduleReplanBody,
        confirmLabel: l.adminScheduleReplanConfirm,
      );
      if (!ok || !mounted) return;
    }
    Navigator.of(context).pop(_build());
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? context.l10n.validationRequired : null;

  String? _url(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    return (uri == null || !uri.hasScheme || !uri.scheme.startsWith('http')) ? context.l10n.adminScheduleBadUrl : null;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final bangla = context.isBn;
    final types = ref.watch(examTypesProvider).value ?? const <ExamTypeInfo>[];
    final typeCodes = {for (final t in types) t.code, _examType};

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? l.adminScheduleNew : l.adminScheduleEdit),
        actions: [
          TextButton(onPressed: _submit, child: Text(l.save)),
          Gap.w8,
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(Gap.lg),
          children: [
            if (widget.initial != null) ...[_ReplanNotice(highlight: _dateChanged), Gap.h16],
            TextFormField(
              controller: _titleBn,
              decoration: InputDecoration(labelText: l.adminScheduleTitleBn),
              validator: _required,
            ),
            Gap.h16,
            TextFormField(
              controller: _titleEn,
              decoration: InputDecoration(labelText: l.adminScheduleTitleEn),
              validator: _required,
            ),
            Gap.h16,
            DropdownButtonFormField<String>(
              initialValue: _examType,
              decoration: InputDecoration(labelText: l.adminScheduleExamType),
              items: [
                for (final code in typeCodes)
                  DropdownMenuItem(
                    value: code,
                    child: Text(
                      types.where((t) => t.code == code).map((t) => t.name(bangla: bangla)).firstOrNull ?? code,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _examType = v ?? _examType),
            ),
            Gap.h16,
            TextFormField(
              controller: _stage,
              decoration: InputDecoration(labelText: l.adminScheduleStage, hintText: l.adminScheduleStageHint),
            ),
            Gap.h16,
            InkWell(
              onTap: _pickDate,
              borderRadius: Radii.button,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: l.adminScheduleDate,
                  prefixIcon: const Icon(Icons.event_rounded),
                  suffixIcon: const Icon(Icons.edit_calendar_outlined),
                ),
                child: Text(Fmt.date(_date, bangla: bangla), style: theme.textTheme.bodyLarge),
              ),
            ),
            Gap.h8,
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.adminScheduleConfirmed),
              subtitle: Text(l.adminScheduleConfirmedHint),
              value: _confirmed,
              onChanged: (v) => setState(() => _confirmed = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.adminScheduleActive),
              subtitle: Text(l.adminScheduleActiveHint),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            Gap.h8,
            TextFormField(
              controller: _sourceUrl,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(labelText: l.adminScheduleSource, prefixIcon: const Icon(Icons.link_rounded)),
              validator: _url,
            ),
            Gap.h16,
            TextFormField(
              controller: _notes,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(labelText: l.adminScheduleNotes, alignLabelWithHint: true),
            ),
            Gap.h24,
            FilledButton(onPressed: _submit, child: Text(l.save)),
          ],
        ),
      ),
    );
  }
}

/// "Changing the date re-plans every affected learner" warning.
class _ReplanNotice extends StatelessWidget {
  const _ReplanNotice({required this.highlight});
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const color = AppColors.warning;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: Gap.card,
      decoration: BoxDecoration(
        color: color.withValues(alpha: highlight ? 0.2 : 0.1),
        borderRadius: Radii.card,
        border: Border.all(color: color.withValues(alpha: highlight ? 0.8 : 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: color),
          Gap.w12,
          Expanded(child: Text(context.l10n.adminScheduleReplanNotice, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
