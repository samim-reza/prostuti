import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/cache/cached_fetcher.dart';
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

/// Which optional setup parts are finished (Home's "Finish setting up").
@immutable
class SetupStatus {
  const SetupStatus({required this.interviewDone, required this.placementDone});

  factory SetupStatus.fromJson(Map<String, dynamic> j) =>
      SetupStatus(interviewDone: j['interview'] == true, placementDone: j['placement'] == true);

  static const complete = SetupStatus(interviewDone: true, placementDone: true);

  final bool interviewDone;
  final bool placementDone;

  bool get isComplete => interviewDone && placementDone;

  Map<String, dynamic> toJson() => {'interview': interviewDone, 'placement': placementDone};
}

class OnboardingRepository implements InterviewAi {
  OnboardingRepository(this._client, this._cache);

  final SupabaseClient _client;
  final CachedFetcher _cache;

  static String _setupKey(String uid) => 'onboarding:setup:$uid';

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

  /// Two tiny indexed reads in parallel. A finished setup is cached for a
  /// month (it can't become unfinished); an unfinished one for 10 minutes and
  /// dropped as soon as a part is completed ([invalidateSetupStatus]).
  Future<SetupStatus> setupStatus() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return SetupStatus.complete;
    return _cache.get<SetupStatus>(
      _setupKey(uid),
      fetch: () async {
        final (interview, placement) = await (
          guard(() => _client.from('onboarding_interviews').select('completed_at').eq('user_id', uid).maybeSingle()),
          guard(
            () => _client
                .from('exam_sessions')
                .select('id')
                .eq('user_id', uid)
                .eq('kind', 'placement')
                .eq('status', 'submitted')
                .limit(1),
          ),
        ).wait;
        return SetupStatus(interviewDone: interview?['completed_at'] != null, placementDone: placement.isNotEmpty);
      },
      encode: (v) => v.toJson(),
      decode: (j) => SetupStatus.fromJson(Map<String, dynamic>.from(j! as Map)),
      policy: const CachePolicy(ttl: Duration(days: 30), negativeTtl: Duration(minutes: 10)),
      isEmpty: (v) => !v.isComplete,
    );
  }

  Future<void> invalidateSetupStatus() async {
    final uid = _client.auth.currentUser?.id;
    if (uid != null) await _cache.invalidate(_setupKey(uid));
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
  (ref) => OnboardingRepository(ref.watch(supabaseProvider), ref.watch(cachedFetcherProvider)),
);

/// Finished parts of the optional setup, per signed-in user.
final setupStatusProvider = FutureProvider<SetupStatus>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return SetupStatus.complete;
  return ref.watch(onboardingRepositoryProvider).setupStatus();
});

/// Call after the interview or the level test was completed.
Future<void> refreshSetupStatus(WidgetRef ref) async {
  await ref.read(onboardingRepositoryProvider).invalidateSetupStatus();
  ref.invalidate(setupStatusProvider);
}

final interviewAiProvider = Provider<InterviewAi>((ref) => ref.watch(onboardingRepositoryProvider));
