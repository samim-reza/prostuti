import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:prostuti/features/onboarding/application/interview_controller.dart';
import 'package:prostuti/features/onboarding/data/interview_models.dart';
import 'package:prostuti/features/onboarding/presentation/widgets/chat_widgets.dart';
import 'package:prostuti/features/onboarding/presentation/widgets/interview_texts.dart';

/// Step 2: a short chat with "প্রস্তুতি এআই" — core questions with quick
/// replies, up to two AI follow-ups and an AI summary. The AI part never
/// blocks: if the function is down the interview simply continues.
class OnboardingInterviewScreen extends ConsumerStatefulWidget {
  const OnboardingInterviewScreen({super.key});

  @override
  ConsumerState<OnboardingInterviewScreen> createState() => _OnboardingInterviewScreenState();
}

class _OnboardingInterviewScreenState extends ConsumerState<OnboardingInterviewScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    unawaited(Future.microtask(() => ref.read(interviewControllerProvider.notifier).start()));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = ref.watch(interviewControllerProvider);
    ref.listen(
      interviewControllerProvider.select((s) => (s.messages.length, s.typing, s.stage)),
      (_, _) => _scrollToEnd(),
    );
    final itemCount = state.messages.length + (state.typing ? 1 : 0);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: Gap.lg,
        title: Row(
          children: [
            const BotAvatar(size: 38),
            Gap.w12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.onboardingBotName, style: theme.textTheme.titleMedium),
                  Text(
                    state.typing ? l.onboardingBotTyping : l.onboardingStepOf(context.n(2), context.n(4)),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: state.typing ? AppColors.success : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: state.progress),
            duration: const Duration(milliseconds: 400),
            builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 4),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(Gap.md, Gap.lg, Gap.md, Gap.lg),
              itemCount: itemCount,
              itemBuilder: (context, i) {
                if (i >= state.messages.length) {
                  return Semantics(label: l.onboardingBotTyping, child: const TypingIndicator());
                }
                final entry = state.messages[i];
                final prevIsBot = i > 0 && state.messages[i - 1] is! UserReply;
                return _MessageView(entry: entry, showAvatar: !prevIsBot);
              },
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.bottomCenter,
            child: _Composer(
              key: ValueKey('${state.stage.name}-${state.questionIndex}-${state.followupIndex}-${state.typing}'),
              state: state,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({required this.entry, required this.showAvatar});

  final ChatEntry entry;
  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge;
    return switch (entry) {
      BotQuestion(:final questionId) => ChatBubble(
        fromBot: true,
        showAvatar: showAvatar,
        child: Text(interviewQuestionText(context, questionId), style: style),
      ),
      BotText(:final text) => ChatBubble(
        fromBot: true,
        showAvatar: showAvatar,
        child: Text(text, style: style),
      ),
      final BotNote note => ChatBubble(
        fromBot: true,
        showAvatar: showAvatar,
        child: Text(interviewNoteText(context, note), style: style),
      ),
      BotSummary(:final profile) => ChatBubble(
        fromBot: true,
        showAvatar: showAvatar,
        child: _SummaryContent(profile: profile),
      ),
      final UserReply reply => ChatBubble(
        fromBot: false,
        child: Text(
          interviewReplyText(context, reply),
          style: style?.copyWith(
            color: Theme.of(context).colorScheme.onPrimary,
            fontStyle: reply.skipped ? FontStyle.italic : null,
          ),
        ),
      ),
    };
  }
}

class _SummaryContent extends StatelessWidget {
  const _SummaryContent({required this.profile});

  final AiProfile profile;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget chips(List<String> items, Color color) => Wrap(
      spacing: Gap.xs + 2,
      runSpacing: Gap.xs + 2,
      children: [
        for (final s in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Gap.sm + 2, vertical: Gap.xxs + 1),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: Radii.chip),
            child: Text(s, style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurface)),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome_rounded, size: 18, color: scheme.primary),
            Gap.w8,
            Flexible(child: Text(l.onboardingSummaryTitle, style: theme.textTheme.titleSmall)),
          ],
        ),
        Gap.h8,
        Text(profile.summary, style: theme.textTheme.bodyLarge),
        if (profile.strengths.isNotEmpty) ...[
          Gap.h12,
          Text(l.onboardingSummaryStrengths, style: theme.textTheme.labelLarge),
          Gap.h4,
          chips(profile.strengths, AppColors.success),
        ],
        if (profile.focusAreas.isNotEmpty) ...[
          Gap.h12,
          Text(l.onboardingSummaryFocus, style: theme.textTheme.labelLarge),
          Gap.h4,
          chips(profile.focusAreas, AppColors.warning),
        ],
      ],
    );
  }
}

/// The input area for whatever the bot is currently asking.
class _Composer extends ConsumerStatefulWidget {
  const _Composer({required this.state, super.key});

  final InterviewState state;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final _text = TextEditingController();
  final _selected = <String>{};
  String? _error;

  InterviewController get _controller => ref.read(interviewControllerProvider.notifier);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _sendText() async {
    final ok = await _controller.answerText(_text.text);
    if (!mounted) return;
    if (ok) {
      _text.clear();
    } else {
      setState(() => _error = context.l10n.onboardingInvalidAnswer);
    }
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 24),
      firstDate: DateTime(now.year - 60),
      lastDate: DateTime(now.year - 14, now.month, now.day),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (picked != null) await _controller.answerDate(picked);
  }

  Future<void> _save() async {
    try {
      await _controller.save();
      // The router moves on to the level test once the step is saved.
    } on Object catch (e) {
      if (!mounted) return;
      if (AppFailure.from(e) is NetworkFailure) {
        showInfoSnack(context, context.l10n.offlineUnavailable);
      } else {
        showErrorSnack(context, e);
      }
    }
  }

  Widget _chips(List<(String key, String label)> options, void Function(String key) onTap) => Wrap(
    spacing: Gap.sm,
    runSpacing: Gap.sm,
    alignment: WrapAlignment.end,
    children: [
      for (final o in options)
        ActionChip(
          label: Text(o.$2),
          onPressed: () => onTap(o.$1),
          side: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
        ),
    ],
  );

  Widget _textInput({required String hint, bool numeric = false, bool optional = false}) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _text,
                autofocus: true,
                minLines: 1,
                maxLines: numeric ? 1 : 4,
                maxLength: numeric ? 4 : 500,
                keyboardType: numeric ? TextInputType.number : TextInputType.multiline,
                inputFormatters: numeric ? [FilteringTextInputFormatter.allow(RegExp('[0-9০-৯]'))] : null,
                textInputAction: numeric ? TextInputAction.send : TextInputAction.newline,
                onSubmitted: numeric ? (_) => _sendText() : null,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: InputDecoration(hintText: hint, errorText: _error, counterText: ''),
              ),
            ),
            Gap.w8,
            IconButton.filled(
              tooltip: l.onboardingSend,
              onPressed: _sendText,
              icon: const Icon(Icons.send_rounded),
              style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
            ),
          ],
        ),
        if (optional) TextButton(onPressed: _controller.skip, child: Text(l.onboardingSkip)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = widget.state;
    final scheme = Theme.of(context).colorScheme;

    Widget? content;
    if (!s.typing) {
      final q = s.currentQuestion;
      final follow = s.currentFollowup;
      if (q != null) {
        content = switch (q.input) {
          InterviewInput.single => _chips([
            for (final o in q.options) (o, interviewOptionLabel(context, o)),
          ], (k) => unawaited(_controller.answerOptions([k]))),
          InterviewInput.multi => _SubjectPicker(
            questionId: q.id,
            selected: _selected,
            exclude: q.id == 'weak_subjects'
                ? ((s.answers['strong_subjects'] as List?)?.map((e) => '$e').toSet() ?? const {})
                : const {},
            onChanged: () => setState(() {}),
            onConfirm: (labels) => _controller.answerOptions(_selected.toList(), labels: labels),
          ),
          InterviewInput.text => _textInput(
            hint: q.id == 'institution' ? l.onboardingHintInstitution : l.onboardingHintChallenge,
            optional: q.optional,
          ),
          InterviewInput.year => Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _chips([('studying', l.onboardingOptStudying)], (k) => unawaited(_controller.answerOptions([k]))),
              Gap.h8,
              _textInput(hint: l.onboardingHintYear, numeric: true, optional: true),
            ],
          ),
          InterviewInput.date => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.onboardingDobPrivacy,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              Gap.h8,
              FilledButton.tonalIcon(
                onPressed: _pickDob,
                icon: const Icon(Icons.cake_outlined),
                label: Text(l.onboardingPickDob),
              ),
              TextButton(onPressed: _controller.skip, child: Text(l.onboardingSkip)),
            ],
          ),
        };
      } else if (follow != null) {
        content = _textInput(hint: l.onboardingHintFollowup, optional: true);
      } else if (s.stage == InterviewStage.aiOffline) {
        content = _chips([
          ('retry', l.onboardingAiRetry),
          ('skip', l.onboardingAiSkip),
        ], (k) => unawaited(k == 'retry' ? _controller.retryAi() : _controller.skipAi()));
      } else if (s.stage == InterviewStage.minutes) {
        content = _chips([
          ('yes', l.onboardingOptYesMinutes),
          ('no', l.onboardingOptNoMinutes),
        ], (k) => unawaited(_controller.acceptMinutes(accept: k == 'yes')));
      } else if (s.stage == InterviewStage.done) {
        content = FilledButton.icon(
          onPressed: s.saving ? null : _save,
          icon: s.saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
              : const Icon(Icons.arrow_forward_rounded),
          label: Text(l.onboardingToPlacement),
        );
      }
    }
    if (content == null) return const SizedBox(width: double.infinity);
    return Material(
      color: scheme.surface,
      elevation: 6,
      shadowColor: Colors.black26,
      child: SafeArea(
        top: false,
        child: Padding(padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.md), child: content),
      ),
    );
  }
}

/// Multi-select chips from the subject catalog with a confirm button.
class _SubjectPicker extends ConsumerWidget {
  const _SubjectPicker({
    required this.questionId,
    required this.selected,
    required this.exclude,
    required this.onChanged,
    required this.onConfirm,
  });

  final String questionId;
  final Set<String> selected;
  final Set<String> exclude;
  final VoidCallback onChanged;
  final void Function(List<String> labels) onConfirm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final subjects = ref.watch(subjectsProvider);
    final list = (subjects.value ?? const <Subject>[]).where((s) => !exclude.contains('${s.id}')).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (subjects.isLoading && !subjects.hasValue)
          const Center(
            child: Padding(padding: EdgeInsets.all(Gap.md), child: CircularProgressIndicator()),
          )
        else
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.3),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                children: [
                  for (final s in list)
                    FilterChip(
                      avatar: Icon(s.iconData, size: 18, color: s.color),
                      label: Text(s.name(context)),
                      selected: selected.contains('${s.id}'),
                      onSelected: (on) {
                        if (on) {
                          selected.add('${s.id}');
                        } else {
                          selected.remove('${s.id}');
                        }
                        onChanged();
                      },
                    ),
                ],
              ),
            ),
          ),
        Gap.h12,
        FilledButton(
          onPressed: () => onConfirm([
            for (final s in list)
              if (selected.contains('${s.id}')) s.name(context),
          ]),
          child: Text(
            selected.isEmpty ? l.onboardingNoneOfThese : l.onboardingConfirmCount(context.n(selected.length)),
          ),
        ),
      ],
    );
  }
}
