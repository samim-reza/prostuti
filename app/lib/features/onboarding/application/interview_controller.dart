import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/config/app_settings.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/utils/bd_time.dart';
import 'package:prostuti/features/onboarding/data/interview_models.dart';
import 'package:prostuti/features/onboarding/data/onboarding_repository.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';

// -----------------------------------------------------------------------------
// Script
// -----------------------------------------------------------------------------
enum InterviewInput { single, multi, text, year, date }

/// One core question. Labels live in l10n (`onboardingQ_<id>` / option keys);
/// the controller only deals with stable keys, so answers are language-free.
@immutable
class InterviewQuestion {
  const InterviewQuestion(this.id, this.input, {this.options = const [], this.optional = false, this.subjects = false});

  final String id;
  final InterviewInput input;
  final List<String> options;
  final bool optional;

  /// Options come from the subject catalog (ids) instead of [options].
  final bool subjects;
}

const interviewScript = <InterviewQuestion>[
  InterviewQuestion('education_level', InterviewInput.single, options: ['ssc', 'hsc', 'bachelor', 'masters']),
  InterviewQuestion('background', InterviewInput.single, options: ['science', 'arts', 'commerce', 'other']),
  InterviewQuestion('institution', InterviewInput.text, optional: true),
  InterviewQuestion('graduation_year', InterviewInput.year, options: ['studying'], optional: true),
  InterviewQuestion('occupation', InterviewInput.single, options: ['student', 'employed', 'job_seeking']),
  InterviewQuestion('bcs_attempts', InterviewInput.single, options: ['0', '1', '2', '3+']),
  InterviewQuestion('strong_subjects', InterviewInput.multi, optional: true, subjects: true),
  InterviewQuestion('weak_subjects', InterviewInput.multi, optional: true, subjects: true),
  InterviewQuestion('study_time', InterviewInput.single, options: ['dawn', 'morning', 'noon', 'afternoon', 'night']),
  InterviewQuestion('challenge', InterviewInput.text, optional: true),
  InterviewQuestion('date_of_birth', InterviewInput.date, optional: true),
];

/// Accepts ASCII or Bangla digits; plausible graduation years only.
int? parseGraduationYear(String input, {DateTime? now}) {
  const bn = '০১২৩৪৫৬৭৮৯';
  final ascii = input.trim().split('').map((c) {
    final i = bn.indexOf(c);
    return i >= 0 ? '$i' : c;
  }).join();
  final year = int.tryParse(ascii);
  final current = (now ?? DateTime.now()).year;
  if (year == null || year < 1970 || year > current + 6) return null;
  return year;
}

// -----------------------------------------------------------------------------
// Chat entries
// -----------------------------------------------------------------------------
enum InterviewNote { welcome, followupIntro, aiOffline, recommendMinutes, closing, closingNoAi }

@immutable
sealed class ChatEntry {
  const ChatEntry();
}

/// A core question (text resolved from l10n by the UI).
final class BotQuestion extends ChatEntry {
  const BotQuestion(this.questionId);
  final String questionId;
}

/// An AI follow-up question (already in the user's language).
final class BotText extends ChatEntry {
  const BotText(this.text);
  final String text;
}

final class BotNote extends ChatEntry {
  const BotNote(this.note, {this.minutes});
  final InterviewNote note;
  final int? minutes;
}

final class BotSummary extends ChatEntry {
  const BotSummary(this.profile);
  final AiProfile profile;
}

/// What the user answered. [options] are keys (labels resolved by the UI,
/// or given in [labels] for catalog subjects).
final class UserReply extends ChatEntry {
  const UserReply({this.questionId, this.options = const [], this.labels = const [], this.text, this.date});

  final String? questionId;
  final List<String> options;
  final List<String> labels;
  final String? text;
  final DateTime? date;

  bool get skipped => options.isEmpty && (text == null || text!.isEmpty) && date == null;
}

// -----------------------------------------------------------------------------
// State
// -----------------------------------------------------------------------------
enum InterviewStage { asking, followup, aiLoading, aiOffline, minutes, done }

@immutable
class InterviewState {
  const InterviewState({
    this.messages = const [],
    this.stage = InterviewStage.asking,
    this.typing = true,
    this.questionIndex = 0,
    this.followups = const [],
    this.followupIndex = 0,
    this.answers = const {},
    this.followupAnswers = const [],
    this.aiProfile,
    this.dateOfBirth,
    this.acceptedMinutes,
    this.aiFailed = false,
    this.saving = false,
  });

  final List<ChatEntry> messages;
  final InterviewStage stage;

  /// The bot is "typing" (delay or waiting for the AI): no input is shown.
  final bool typing;
  final int questionIndex;
  final List<AiFollowup> followups;
  final int followupIndex;
  final Map<String, dynamic> answers;
  final List<FollowupAnswer> followupAnswers;
  final AiProfile? aiProfile;
  final DateTime? dateOfBirth;
  final int? acceptedMinutes;
  final bool aiFailed;
  final bool saving;

  InterviewQuestion? get currentQuestion =>
      stage == InterviewStage.asking && !typing && questionIndex < interviewScript.length
      ? interviewScript[questionIndex]
      : null;

  AiFollowup? get currentFollowup =>
      stage == InterviewStage.followup && !typing && followupIndex < followups.length ? followups[followupIndex] : null;

  /// 0…1 for the progress bar.
  double get progress {
    final total = interviewScript.length + 1;
    final done = switch (stage) {
      InterviewStage.asking => questionIndex,
      InterviewStage.done => total,
      _ => interviewScript.length,
    };
    return (done / total).clamp(0, 1).toDouble();
  }

  InterviewState copyWith({
    List<ChatEntry>? messages,
    InterviewStage? stage,
    bool? typing,
    int? questionIndex,
    List<AiFollowup>? followups,
    int? followupIndex,
    Map<String, dynamic>? answers,
    List<FollowupAnswer>? followupAnswers,
    AiProfile? aiProfile,
    DateTime? dateOfBirth,
    int? acceptedMinutes,
    bool? aiFailed,
    bool? saving,
  }) => InterviewState(
    messages: messages ?? this.messages,
    stage: stage ?? this.stage,
    typing: typing ?? this.typing,
    questionIndex: questionIndex ?? this.questionIndex,
    followups: followups ?? this.followups,
    followupIndex: followupIndex ?? this.followupIndex,
    answers: answers ?? this.answers,
    followupAnswers: followupAnswers ?? this.followupAnswers,
    aiProfile: aiProfile ?? this.aiProfile,
    dateOfBirth: dateOfBirth ?? this.dateOfBirth,
    acceptedMinutes: acceptedMinutes ?? this.acceptedMinutes,
    aiFailed: aiFailed ?? this.aiFailed,
    saving: saving ?? this.saving,
  );
}

// -----------------------------------------------------------------------------
// Controller
// -----------------------------------------------------------------------------
/// Bot "typing" pause before each message (zero in tests).
final interviewTypingDelayProvider = Provider<Duration>((ref) => const Duration(milliseconds: 650));

/// Connectivity probe (overridable in tests).
final interviewOnlineCheckProvider = Provider<bool Function()>(
  (ref) =>
      () => ConnectivityService.instance.isOnline,
);

class InterviewController extends Notifier<InterviewState> {
  bool _started = false;

  @override
  InterviewState build() => const InterviewState();

  InterviewAi get _ai => ref.read(interviewAiProvider);
  String get _locale => ref.read(appSettingsProvider).locale.languageCode == 'en' ? 'en' : 'bn';
  bool get _online => ref.read(interviewOnlineCheckProvider)();

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _say(const BotNote(InterviewNote.welcome));
    await _ask(0);
  }

  Future<void> _say(ChatEntry entry) async {
    if (!ref.mounted) return;
    state = state.copyWith(typing: true);
    final delay = ref.read(interviewTypingDelayProvider);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (!ref.mounted) return;
    state = state.copyWith(typing: false, messages: [...state.messages, entry]);
  }

  void _reply(UserReply reply) => state = state.copyWith(messages: [...state.messages, reply]);

  Future<void> _ask(int index) async {
    if (index >= interviewScript.length) return _afterCore();
    state = state.copyWith(stage: InterviewStage.asking, questionIndex: index, typing: true);
    await _say(BotQuestion(interviewScript[index].id));
  }

  /// Answers a chip question (single or multi). [labels] are display names
  /// (used for catalog subjects, which have no l10n keys).
  Future<void> answerOptions(List<String> keys, {List<String> labels = const []}) async {
    final q = state.currentQuestion;
    if (q == null || q.input == InterviewInput.text || q.input == InterviewInput.date) return;
    if (keys.isEmpty && !q.optional) return;
    if (keys.isEmpty && q.input != InterviewInput.multi) return skip();
    final answers = {...state.answers};
    if (q.subjects) {
      answers[q.id] = keys.map(int.tryParse).whereType<int>().toList();
      if (labels.isNotEmpty) answers['${q.id}_names'] = labels;
    } else if (q.input == InterviewInput.multi) {
      answers[q.id] = keys;
    } else {
      answers[q.id] = keys.first;
    }
    state = state.copyWith(answers: answers);
    _reply(UserReply(questionId: q.id, options: keys.isEmpty ? const ['none'] : keys, labels: labels));
    await _ask(state.questionIndex + 1);
  }

  /// Free-text answer for a text/year question or an AI follow-up. Returns
  /// false when the input is invalid (e.g. an impossible year).
  Future<bool> answerText(String raw) async {
    final text = raw.trim();
    final follow = state.currentFollowup;
    if (follow != null) {
      if (text.isEmpty) return false;
      await _answerFollowup(follow, text);
      return true;
    }
    final q = state.currentQuestion;
    if (q == null || text.isEmpty) return false;
    final Object value;
    if (q.input == InterviewInput.year) {
      final year = parseGraduationYear(text);
      if (year == null) return false;
      value = year;
    } else if (q.input == InterviewInput.text) {
      value = text.length > 500 ? text.substring(0, 500) : text;
    } else {
      return false;
    }
    state = state.copyWith(answers: {...state.answers, q.id: value});
    _reply(UserReply(questionId: q.id, text: '$value'));
    await _ask(state.questionIndex + 1);
    return true;
  }

  Future<void> answerDate(DateTime date) async {
    final q = state.currentQuestion;
    if (q == null || q.input != InterviewInput.date) return;
    final d = DateTime.utc(date.year, date.month, date.day);
    final today = BdTime.today();
    var age = today.year - d.year;
    if (today.month < d.month || (today.month == d.month && today.day < d.day)) age--;
    state = state.copyWith(dateOfBirth: d, answers: {...state.answers, 'age_years': age});
    _reply(UserReply(questionId: q.id, date: d));
    await _ask(state.questionIndex + 1);
  }

  /// Skips an optional core question or an AI follow-up.
  Future<void> skip() async {
    final follow = state.currentFollowup;
    if (follow != null) return _answerFollowup(follow, '');
    final q = state.currentQuestion;
    if (q == null || !q.optional) return;
    _reply(UserReply(questionId: q.id));
    await _ask(state.questionIndex + 1);
  }

  // --- AI part ---------------------------------------------------------------
  Future<void> _afterCore() async {
    if (!_online) return _offline();
    state = state.copyWith(stage: InterviewStage.aiLoading, typing: true);
    try {
      final list = await _ai.followups(state.answers, locale: _locale);
      if (!ref.mounted) return;
      if (list.isEmpty) {
        await _finalize();
        return;
      }
      state = state.copyWith(followups: list);
      await _say(const BotNote(InterviewNote.followupIntro));
      await _askFollowup(0);
    } on Object catch (e) {
      if (!ref.mounted) return;
      if (AppFailure.from(e) is NetworkFailure) return _offline();
      // Function missing/failing: never block onboarding on the AI.
      state = state.copyWith(aiFailed: true);
      await _finish();
    }
  }

  Future<void> _offline() async {
    state = state.copyWith(stage: InterviewStage.aiOffline, typing: true);
    await _say(const BotNote(InterviewNote.aiOffline));
  }

  /// "Try again" in the offline prompt.
  Future<void> retryAi() async {
    if (state.stage != InterviewStage.aiOffline || state.typing) return;
    await _afterCore();
  }

  /// "Continue without" in the offline prompt.
  Future<void> skipAi() async {
    if (state.stage != InterviewStage.aiOffline || state.typing) return;
    _reply(const UserReply(questionId: 'ai_skip'));
    state = state.copyWith(aiFailed: true);
    await _finish();
  }

  Future<void> _askFollowup(int index) async {
    if (index >= state.followups.length) return _finalize();
    state = state.copyWith(stage: InterviewStage.followup, followupIndex: index, typing: true);
    await _say(BotText(state.followups[index].question));
  }

  Future<void> _answerFollowup(AiFollowup follow, String answer) async {
    final text = answer.length > 500 ? answer.substring(0, 500) : answer;
    state = state.copyWith(
      followupAnswers: [
        ...state.followupAnswers,
        FollowupAnswer(id: follow.id, question: follow.question, answer: text),
      ],
    );
    _reply(UserReply(text: text));
    await _askFollowup(state.followupIndex + 1);
  }

  Future<void> _finalize() async {
    state = state.copyWith(stage: InterviewStage.aiLoading, typing: true);
    try {
      final profile = await _ai.finalize(state.answers, state.followupAnswers, locale: _locale);
      if (!ref.mounted) return;
      if (profile != null) {
        state = state.copyWith(aiProfile: profile);
        await _say(BotSummary(profile));
        final rec = profile.recommendedDailyMinutes;
        final current = ref.read(currentProfileProvider).value?.dailyStudyMinutes;
        if (rec != null && rec != current) {
          state = state.copyWith(stage: InterviewStage.minutes, typing: true);
          await _say(BotNote(InterviewNote.recommendMinutes, minutes: rec));
          return;
        }
      } else {
        state = state.copyWith(aiFailed: true);
      }
    } on Object {
      if (!ref.mounted) return;
      state = state.copyWith(aiFailed: true);
    }
    await _finish();
  }

  /// Yes/no to the AI's recommended daily study time.
  Future<void> acceptMinutes({required bool accept}) async {
    if (state.stage != InterviewStage.minutes || state.typing) return;
    final rec = state.aiProfile?.recommendedDailyMinutes;
    if (accept && rec != null) state = state.copyWith(acceptedMinutes: rec);
    _reply(UserReply(options: [if (accept) 'yes' else 'no']));
    await _finish();
  }

  Future<void> _finish() async {
    state = state.copyWith(stage: InterviewStage.done, typing: true);
    await _say(BotNote(state.aiProfile != null ? InterviewNote.closing : InterviewNote.closingNoAi));
  }

  // --- Persistence -----------------------------------------------------------
  /// Saves the interview + profile fields and moves onboarding to the
  /// placement step (the router then navigates). Throws an [AppFailure].
  Future<void> save() async {
    if (state.stage != InterviewStage.done || state.saving) return;
    if (!_online) throw const NetworkFailure();
    state = state.copyWith(saving: true);
    try {
      final a = state.answers;
      await ref
          .read(onboardingRepositoryProvider)
          .saveInterview(answers: a, followups: state.followupAnswers, aiProfile: state.aiProfile);
      final dob = state.dateOfBirth;
      if (dob != null) {
        await ref.read(profileRepositoryProvider).updatePrivate({
          'date_of_birth':
              '${dob.year.toString().padLeft(4, '0')}-${dob.month.toString().padLeft(2, '0')}-'
              '${dob.day.toString().padLeft(2, '0')}',
        });
      }
      await ref.read(currentProfileProvider.notifier).save({
        'education': {
          for (final k in const ['education_level', 'background', 'institution', 'graduation_year'])
            if (a[k] != null) (k == 'education_level' ? 'level' : k): a[k],
        },
        if (a['occupation'] is String) 'occupation': a['occupation'],
        if (state.acceptedMinutes != null) 'daily_study_minutes': state.acceptedMinutes,
        'onboarding_step': 'placement',
      });
    } finally {
      if (ref.mounted) state = state.copyWith(saving: false);
    }
  }
}

final interviewControllerProvider = NotifierProvider.autoDispose<InterviewController, InterviewState>(
  InterviewController.new,
);
