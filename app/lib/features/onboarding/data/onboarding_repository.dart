import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/network/rpc.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/features/onboarding/data/interview_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The AI side of the interview (an interface so tests can fake it).
abstract interface class InterviewAi {
  /// Up to two personalised follow-up questions.
  Future<List<AiFollowup>> followups(Map<String, dynamic> answers, {required String locale});

  /// The AI's summary of the candidate (null when the reply is unusable).
  Future<AiProfile?> finalize(
    Map<String, dynamic> answers,
    List<FollowupAnswer> followupAnswers, {
    required String locale,
  });
}

class OnboardingRepository implements InterviewAi {
  OnboardingRepository(this._client);

  final SupabaseClient _client;

  static const _function = 'onboarding-interview';
  static const aiTimeout = Duration(seconds: 25);

  Future<Object?> _invoke(Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke(_function, body: body).timeout(aiTimeout);
      final data = res.data;
      if (data is Map && data['error'] != null) throw ServerFailure(data['error'].toString());
      return data;
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  @override
  Future<List<AiFollowup>> followups(Map<String, dynamic> answers, {required String locale}) async {
    final data = await _invoke({'answers': answers, 'locale': locale});
    return data is Map ? AiFollowup.listFrom(data['followups']) : const [];
  }

  @override
  Future<AiProfile?> finalize(
    Map<String, dynamic> answers,
    List<FollowupAnswer> followupAnswers, {
    required String locale,
  }) async {
    final data = await _invoke({
      'answers': answers,
      'followup_answers': followupAnswers.map((f) => f.toJson()).toList(),
      'finalize': true,
      'locale': locale,
    });
    return AiProfile.parse(data);
  }

  /// Persists the whole interview (owner-only table).
  Future<void> saveInterview({
    required Map<String, dynamic> answers,
    required List<FollowupAnswer> followups,
    AiProfile? aiProfile,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthFailure('not_authenticated');
    await guard(
      () => _client.from('onboarding_interviews').upsert({
        'user_id': uid,
        'answers': answers,
        'followups': followups.map((f) => f.toJson()).toList(),
        'ai_profile': aiProfile?.toJson(),
        'completed_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }
}

final onboardingRepositoryProvider = Provider<OnboardingRepository>(
  (ref) => OnboardingRepository(ref.watch(supabaseProvider)),
);

final interviewAiProvider = Provider<InterviewAi>((ref) => ref.watch(onboardingRepositoryProvider));
