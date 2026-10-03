import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/admin/data/admin_models.dart';

/// Full-screen editor for a question's stem, options, answer key and
/// explanation. Pops with a [QuestionEdit] (or null when cancelled).
class QuestionEditorPage extends StatefulWidget {
  const QuestionEditorPage({required this.question, super.key});
  final AdminQuestion question;

  static Future<QuestionEdit?> open(BuildContext context, AdminQuestion q) => Navigator.of(context)
      .push(MaterialPageRoute<QuestionEdit>(fullscreenDialog: true, builder: (_) => QuestionEditorPage(question: q)));

  @override
  State<QuestionEditorPage> createState() => _QuestionEditorPageState();
}

class _QuestionEditorPageState extends State<QuestionEditorPage> {
  late final TextEditingController _stem;
  late final TextEditingController _explanation;
  late final List<TextEditingController> _options;
  late int _correct;

  @override
  void initState() {
    super.initState();
    final q = widget.question;
    _stem = TextEditingController(text: q.stem);
    _explanation = TextEditingController(text: q.explanation ?? '');
    _options = [for (final o in q.options) TextEditingController(text: o)];
    _correct = q.correctIndex.clamp(0, _options.isEmpty ? 0 : _options.length - 1);
  }

  @override
  void dispose() {
    _stem.dispose();
    _explanation.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  QuestionEdit get _edit => QuestionEdit(
    stem: _stem.text,
    options: [for (final c in _options) c.text],
    correctIndex: _correct,
    explanation: _explanation.text,
  );

  void _addOption() {
    if (_options.length >= 5) return;
    setState(() => _options.add(TextEditingController()));
  }

  void _removeOption(int i) {
    if (_options.length <= 2) return;
    setState(() {
      _options.removeAt(i).dispose();
      if (_correct == i) {
        _correct = 0;
      } else if (_correct > i) {
        _correct -= 1;
      }
    });
  }

  void _submit() {
    final l = context.l10n;
    final edit = _edit;
    final error = validateQuestionEdit(edit);
    if (error != null) {
      showInfoSnack(context, switch (error) {
        QuestionEditError.stemLength => l.adminEditErrorStem,
        QuestionEditError.optionCount => l.adminEditErrorOptionCount,
        QuestionEditError.emptyOption => l.adminEditErrorEmptyOption,
        QuestionEditError.correctOutOfRange => l.adminEditErrorCorrect,
      });
      return;
    }
    Navigator.of(context).pop(edit);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.adminEditQuestion(context.n(widget.question.id))),
        actions: [
          TextButton(onPressed: _submit, child: Text(l.save)),
          Gap.w8,
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: [
          TextField(
            controller: _stem,
            minLines: 2,
            maxLines: 6,
            maxLength: 2000,
            decoration: InputDecoration(labelText: l.adminEditStem, alignLabelWithHint: true),
          ),
          Gap.h8,
          Row(
            children: [
              Expanded(child: Text(l.adminEditOptions, style: theme.textTheme.titleSmall)),
              Text(l.adminEditCorrectHint, style: theme.textTheme.bodySmall),
            ],
          ),
          Gap.h8,
          RadioGroup<int>(
            groupValue: _correct,
            onChanged: (v) => setState(() => _correct = v ?? _correct),
            child: Column(
              children: [
                for (var i = 0; i < _options.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.sm),
                    child: Row(
                      children: [
                        Radio<int>(value: i),
                        Expanded(
                          child: TextField(
                            controller: _options[i],
                            decoration: InputDecoration(labelText: l.adminEditOption(context.n(i + 1))),
                          ),
                        ),
                        IconButton(
                          tooltip: l.adminEditRemoveOption,
                          onPressed: _options.length > 2 ? () => _removeOption(i) : null,
                          icon: const Icon(Icons.remove_circle_outline_rounded),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (_options.length < 5)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addOption,
                icon: const Icon(Icons.add_rounded),
                label: Text(l.adminEditAddOption),
              ),
            ),
          Gap.h16,
          TextField(
            controller: _explanation,
            minLines: 3,
            maxLines: 8,
            decoration: InputDecoration(labelText: l.adminEditExplanation, alignLabelWithHint: true),
          ),
          Gap.h24,
          FilledButton(onPressed: _submit, child: Text(l.adminEditSave)),
        ],
      ),
    );
  }
}
