import 'package:flutter/widgets.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';

/// Bangla/English text for the backend codes raised by the current-affairs
/// RPCs (`claim_note_download`, `start_exam('daily')`).
String? currentAffairsFailureResolver(BuildContext context, String code) {
  final l = context.l10n;
  return switch (code) {
    'no_notes_today' => l.dailyNotesErrNoNotesToday,
    'invalid_method' => l.dailyNotesErrInvalidMethod,
    'no_daily_exam' => l.dailyExamErrNoDailyExam,
    'already_attempted' => l.dailyExamErrAlreadyAttempted,
    _ => null,
  };
}

/// Idempotent: the resolver is a top-level function, so re-registering the
/// same tear-off is a no-op.
void registerCurrentAffairsMessages() => registerFailureMessages(currentAffairsFailureResolver);

/// `failureMessage()` maps PT404/PT409 to generic text before consulting
/// feature resolvers, so our own codes are checked first here.
String currentAffairsErrorText(BuildContext context, Object error) {
  final failure = AppFailure.from(error);
  return currentAffairsFailureResolver(context, failure.code) ?? failureMessage(context, error);
}
