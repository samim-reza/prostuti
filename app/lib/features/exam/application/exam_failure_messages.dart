import 'package:flutter/material.dart';
import 'package:prostuti/core/entitlements/feature_access.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/widgets/state_views.dart';

/// Bangla/English text for the exam & question-bank backend codes.
String? examFailureCodeMessage(BuildContext context, String code) {
  final l = context.l10n;
  return switch (code) {
    'no_questions' => l.examErrNoQuestions,
    'already_attempted' => l.examErrAlreadyAttempted,
    'session_expired' => l.examErrSessionExpired,
    'question_locked' => l.examErrQuestionLocked,
    'subject_not_found' => l.examErrSubjectNotFound,
    'topic_not_found' => l.examErrTopicNotFound,
    'session_not_found' => l.examErrSessionNotFound,
    'no_daily_exam' => l.examErrNoDailyExam,
    'question_not_found' => l.examErrQuestionNotFound,
    _ => null,
  };
}

/// Registers [examFailureCodeMessage] with the global `failureMessage()`.
/// Idempotent (a top-level tear-off is a canonical constant).
void registerExamFailureMessages() => registerFailureMessages(examFailureCodeMessage);

/// Like `failureMessage()`, but also resolves exam codes carried by
/// not-found / conflict / permission failures (PT404/PT409/PT403), which the
/// global resolver only consults for generic server failures.
String examErrorMessage(BuildContext context, Object error) {
  final failure = AppFailure.from(error);
  return examFailureCodeMessage(context, failure.code) ?? failureMessage(context, failure);
}

/// Locked feature → add-on sheet; anything else → snack bar.
void showExamError(BuildContext context, Object error) {
  final failure = AppFailure.from(error);
  if (failure is FeatureLockedFailure) {
    showLockedSheet(context);
    return;
  }
  showInfoSnack(context, examErrorMessage(context, failure));
}

/// True when the backend refused an answer because the question belongs to
/// today's live daily exam.
bool isQuestionLocked(Object error) => AppFailure.from(error).code == 'question_locked';
