// Fakes rethrow whatever error object the test injects.
// ignore_for_file: only_throw_errors
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/core/config/app_settings.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/features/onboarding/application/interview_controller.dart';
import 'package:prostuti/features/onboarding/data/interview_models.dart';
import 'package:prostuti/features/onboarding/data/onboarding_repository.dart';
import 'package:prostuti/features/profile/data/profile.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';

class _FakeAi implements InterviewAi {
  List<AiFollowup> followupList = const [];
  AiProfile? profile;
  Object? followupError;
  Object? finalizeError;
  int followupCalls = 0;
  Map<String, dynamic>? sentAnswers;
  List<FollowupAnswer>? sentFollowups;
  String? sentLocale;

  @override
  Future<List<AiFollowup>> followups(Map<String, dynamic> answers, {required String locale}) async {
    followupCalls++;
    sentAnswers = answers;
    sentLocale = locale;
    if (followupError != null) throw followupError!;
    return followupList;
  }

  @override
  Future<AiProfile?> finalize(
    Map<String, dynamic> answers,
    List<FollowupAnswer> followupAnswers, {
    required String locale,
  }) async {
    sentFollowups = followupAnswers;
    if (finalizeError != null) throw finalizeError!;
    return profile;
  }
}

class _FakeProfile extends CurrentProfileNotifier {
  @override
  Future<Profile?> build() async => const Profile(id: 'u', username: 'rahim');
}

class _FakeSettings extends AppSettingsNotifier {
  @override
  AppSettings build() => const AppSettings(locale: Locale('en'));
}

void main() {
  late _FakeAi ai;
  late ProviderContainer container;
  var online = true;

  setUp(() async {
    ai = _FakeAi();
    online = true;
    container = ProviderContainer(
      overrides: [
        interviewAiProvider.overrideWithValue(ai),
        interviewTypingDelayProvider.overrideWithValue(Duration.zero),
        interviewOnlineCheckProvider.overrideWithValue(() => online),
        currentProfileProvider.overrideWith(_FakeProfile.new),
        appSettingsProvider.overrideWith(_FakeSettings.new),
      ],
    );
    addTearDown(container.dispose);
    container.listen(interviewControllerProvider, (_, _) {});
    await container.read(currentProfileProvider.future);
  });

  InterviewController ctrl() => container.read(interviewControllerProvider.notifier);
  InterviewState st() => container.read(interviewControllerProvider);

  /// Answers every core question with sensible values.
  Future<void> answerCore() async {
    await ctrl().answerOptions(['hsc']);
    await ctrl().answerOptions(['science']);
    await ctrl().answerText('Dhaka University, Economics');
    await ctrl().answerOptions(['studying']);
    await ctrl().answerOptions(['job_seeking']);
    await ctrl().answerOptions(['1']);
    await ctrl().answerOptions(['8', '9'], labels: ['Maths', 'Mental ability']);
    await ctrl().answerOptions([]);
    await ctrl().answerOptions(['night']);
    await ctrl().skip();
    await ctrl().answerDate(DateTime(1999, 1, 15));
  }

  test('asks the core questions in order', () async {
    await ctrl().start();
    expect(st().messages.first, isA<BotNote>());
    expect(st().currentQuestion!.id, 'education_level');

    await ctrl().answerOptions(['hsc']);
    expect(st().currentQuestion!.id, 'background');
    expect(st().answers['education_level'], 'hsc');
    expect(st().messages.whereType<UserReply>().single.options, ['hsc']);
  });

  test('required questions cannot be skipped; invalid years are rejected', () async {
    await ctrl().start();
    await ctrl().skip();
    expect(st().currentQuestion!.id, 'education_level');

    await ctrl().answerOptions(['hsc']);
    await ctrl().answerOptions(['science']);
    await ctrl().answerText('BUET, CSE');
    expect(await ctrl().answerText('1850'), isFalse);
    expect(st().currentQuestion!.id, 'graduation_year');
    expect(await ctrl().answerText('২০২২'), isTrue);
    expect(st().answers['graduation_year'], 2022);
  });

  test('full flow: follow-ups → AI summary → recommended minutes → done', () async {
    ai
      ..followupList = const [
        AiFollowup(id: 'f1', question: 'How many hours do you work?'),
        AiFollowup(id: 'f2', question: 'Which books do you use?'),
      ]
      ..profile = const AiProfile(summary: 'Strong in maths', recommendedDailyMinutes: 150);

    await ctrl().start();
    await answerCore();

    // Subjects are stored as ids (+ display names for the AI).
    expect(ai.sentAnswers!['strong_subjects'], [8, 9]);
    expect(ai.sentAnswers!['strong_subjects_names'], ['Maths', 'Mental ability']);
    expect(ai.sentAnswers!['weak_subjects'], isEmpty);
    expect(ai.sentAnswers!.containsKey('challenge'), isFalse, reason: 'skipped');
    expect(ai.sentAnswers!['age_years'], greaterThanOrEqualTo(27));
    expect(ai.sentLocale, 'en');
    expect(st().dateOfBirth, DateTime.utc(1999, 1, 15));

    expect(st().stage, InterviewStage.followup);
    expect(st().currentFollowup!.id, 'f1');
    await ctrl().answerText('8 hours');
    expect(st().currentFollowup!.id, 'f2');
    await ctrl().skip();

    expect(ai.sentFollowups!.map((f) => f.answer), ['8 hours', '']);
    expect(st().messages.whereType<BotSummary>(), hasLength(1));
    expect(st().stage, InterviewStage.minutes);

    await ctrl().acceptMinutes(accept: true);
    expect(st().acceptedMinutes, 150);
    expect(st().stage, InterviewStage.done);
    expect((st().messages.last as BotNote).note, InterviewNote.closing);
    expect(st().progress, 1);
  });

  test('no follow-ups → straight to the summary; same minutes → no question', () async {
    ai.profile = const AiProfile(summary: 'OK', recommendedDailyMinutes: 120);
    await ctrl().start();
    await answerCore();
    expect(st().stage, InterviewStage.done);
    expect(st().acceptedMinutes, isNull);
  });

  test('function failure falls back without blocking', () async {
    ai.followupError = const ServerFailure('function_error');
    await ctrl().start();
    await answerCore();
    expect(ai.followupCalls, 1);
    expect(st().stage, InterviewStage.done);
    expect(st().aiFailed, isTrue);
    expect(st().aiProfile, isNull);
    expect((st().messages.last as BotNote).note, InterviewNote.closingNoAi);
  });

  test('finalize failure still finishes', () async {
    ai
      ..followupList = const [AiFollowup(id: 'f1', question: 'Q?')]
      ..finalizeError = const NotFoundFailure('not_found');
    await ctrl().start();
    await answerCore();
    await ctrl().answerText('A');
    expect(st().stage, InterviewStage.done);
    expect(st().aiFailed, isTrue);
  });

  test('offline → retry or continue without the AI', () async {
    online = false;
    await ctrl().start();
    await answerCore();
    expect(st().stage, InterviewStage.aiOffline);
    expect(ai.followupCalls, 0);

    // A network failure on retry keeps offering the choice.
    online = true;
    ai.followupError = const NetworkFailure();
    await ctrl().retryAi();
    expect(st().stage, InterviewStage.aiOffline);
    expect(ai.followupCalls, 1);

    await ctrl().skipAi();
    expect(st().stage, InterviewStage.done);
    expect(st().messages.whereType<UserReply>().last.questionId, 'ai_skip');
  });

  test('retry succeeds once back online', () async {
    online = false;
    await ctrl().start();
    await answerCore();
    online = true;
    ai.followupList = const [AiFollowup(id: 'f1', question: 'Q?')];
    await ctrl().retryAi();
    expect(st().stage, InterviewStage.followup);
  });

  test('save refuses to run offline', () async {
    ai.followupError = const ServerFailure('x');
    await ctrl().start();
    await answerCore();
    online = false;
    await expectLater(ctrl().save(), throwsA(isA<NetworkFailure>()));
    expect(st().saving, isFalse);
  });
}
