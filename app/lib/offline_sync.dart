import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/features/bookmarks/data/bookmarks_repository.dart';
import 'package:prostuti/features/chat/data/chat_repository.dart';
import 'package:prostuti/features/daily_notes/data/daily_notes_repository.dart';
import 'package:prostuti/features/exam/data/exam_repository.dart';
import 'package:prostuti/features/exam/data/question_actions_repository.dart';
import 'package:prostuti/features/feed/data/feed_repository.dart';
import 'package:prostuti/features/friends/data/friends_repository.dart';
import 'package:prostuti/features/notifications/data/notifications_repository.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';
import 'package:prostuti/features/question_bank/data/question_bank_repository.dart';
import 'package:prostuti/features/study_plan/data/study_plan_repository.dart';

/// Every repository that owns offline-queue handlers registers them when it
/// is first created. Creating them all at start-up means writes queued in a
/// previous session (a chat message, a submitted exam, practice answers…)
/// sync as soon as the app opens online — not only when the user happens to
/// revisit that feature.
void registerOfflineHandlers(WidgetRef ref) {
  ref
    ..read(bookmarksRepositoryProvider)
    ..read(chatRepositoryProvider)
    ..read(dailyNotesRepositoryProvider)
    ..read(examRepositoryProvider)
    ..read(questionActionsRepositoryProvider)
    ..read(feedRepositoryProvider)
    ..read(friendsRepositoryProvider)
    ..read(notificationsRepositoryProvider)
    ..read(profileRepositoryProvider)
    ..read(questionBankRepositoryProvider)
    ..read(studyPlanRepositoryProvider);
}
