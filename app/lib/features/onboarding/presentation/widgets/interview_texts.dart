import 'package:flutter/widgets.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/features/onboarding/application/interview_controller.dart';

/// l10n for the interview script (the controller only knows stable keys).
String interviewQuestionText(BuildContext context, String id) {
  final l = context.l10n;
  return switch (id) {
    'education_level' => l.onboardingQEducation,
    'background' => l.onboardingQBackground,
    'institution' => l.onboardingQInstitution,
    'graduation_year' => l.onboardingQGraduationYear,
    'occupation' => l.onboardingQOccupation,
    'bcs_attempts' => l.onboardingQAttempts,
    'strong_subjects' => l.onboardingQStrong,
    'weak_subjects' => l.onboardingQWeak,
    'study_time' => l.onboardingQStudyTime,
    'challenge' => l.onboardingQChallenge,
    'date_of_birth' => l.onboardingQDob,
    _ => id,
  };
}

String interviewOptionLabel(BuildContext context, String key) {
  final l = context.l10n;
  return switch (key) {
    'ssc' => l.onboardingOptSsc,
    'hsc' => l.onboardingOptHsc,
    'bachelor' => l.onboardingOptBachelor,
    'masters' => l.onboardingOptMasters,
    'science' => l.onboardingOptScience,
    'arts' => l.onboardingOptArts,
    'commerce' => l.onboardingOptCommerce,
    'other' => l.onboardingOptOther,
    'studying' => l.onboardingOptStudying,
    'student' => l.onboardingOptStudent,
    'employed' => l.onboardingOptEmployed,
    'job_seeking' => l.onboardingOptJobSeeking,
    '0' => l.onboardingOptAttempts0,
    '1' => l.onboardingOptAttempts1,
    '2' => l.onboardingOptAttempts2,
    '3+' => l.onboardingOptAttempts3,
    'dawn' => l.onboardingOptDawn,
    'morning' => l.onboardingOptMorning,
    'noon' => l.onboardingOptNoon,
    'afternoon' => l.onboardingOptAfternoon,
    'night' => l.onboardingOptNight,
    'yes' => l.onboardingOptYesMinutes,
    'no' => l.onboardingOptNoMinutes,
    'none' => l.onboardingOptNone,
    _ => key,
  };
}

String interviewNoteText(BuildContext context, BotNote note) {
  final l = context.l10n;
  return switch (note.note) {
    InterviewNote.welcome => l.onboardingBotWelcome,
    InterviewNote.followupIntro => l.onboardingBotFollowupIntro,
    InterviewNote.aiOffline => l.onboardingBotOffline,
    InterviewNote.recommendMinutes => l.onboardingBotRecommendMinutes(
      Fmt.minutes(note.minutes ?? 0, bangla: context.isBn),
    ),
    InterviewNote.closing => l.onboardingBotClosing,
    InterviewNote.closingNoAi => l.onboardingBotClosingNoAi,
  };
}

/// The text shown in a user's reply bubble.
String interviewReplyText(BuildContext context, UserReply reply) {
  final l = context.l10n;
  if (reply.questionId == 'ai_skip') return l.onboardingAiSkipReply;
  if (reply.skipped) return l.onboardingSkipped;
  if (reply.date != null) return Fmt.date(reply.date!, bangla: context.isBn);
  if (reply.labels.isNotEmpty) return reply.labels.join(', ');
  if (reply.options.isNotEmpty) return reply.options.map((k) => interviewOptionLabel(context, k)).join(', ');
  final text = reply.text ?? '';
  return reply.questionId == 'graduation_year' ? context.n(text) : text;
}
