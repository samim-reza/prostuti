import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/features/onboarding/application/onboarding_flow.dart';
import 'package:prostuti/features/profile/data/profile.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';

/// Saves locally (no network) and records every patch.
class _FakeProfile extends CurrentProfileNotifier {
  _FakeProfile(this.initial);

  final Profile initial;
  final saves = <Map<String, dynamic>>[];

  @override
  Future<Profile?> build() async => initial;

  @override
  Future<Profile> save(Map<String, dynamic> patch) async {
    saves.add(patch);
    final next = Profile.fromJson({...state.value!.toJson(), ...patch});
    state = AsyncData(next);
    return next;
  }
}

/// A stand-in step screen with the two ways forward every real step has.
class _Step extends ConsumerWidget {
  const _Step(this.name, {this.next});

  final String name;
  final OnboardingStep? next;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Column(
      children: [
        Text('screen:$name'),
        if (next != null)
          TextButton(onPressed: () => OnboardingFlow.advance(context, ref, next!), child: const Text('next')),
        TextButton(onPressed: () => OnboardingFlow.finish(context, ref), child: const Text('later')),
      ],
    ),
  );
}

void main() {
  group('onboardingRedirect', () {
    String? go(String loc, OnboardingStep step, {bool later = false}) =>
        onboardingRedirect(loc, step: step, later: later);

    test('during onboarding only the saved step is shown', () {
      expect(go(Routes.home, OnboardingStep.profile), Routes.onboardingProfile);
      expect(go(Routes.onboardingProfile, OnboardingStep.profile), isNull);
      // The reported bug: after "Save and continue" the step is "interview",
      // so the profile screen must give way to the interview.
      expect(go(Routes.onboardingProfile, OnboardingStep.interview), Routes.onboardingInterview);
      expect(go(Routes.onboardingInterview, OnboardingStep.placement), Routes.onboardingPlacement);
      expect(go(Routes.onboardingPlacement, OnboardingStep.plan), Routes.onboardingResult);
      expect(go(Routes.welcome, OnboardingStep.interview), Routes.onboardingInterview);
    });

    test('the level test runs in the exam screens; its result may open before the profile reloads', () {
      expect(go(Routes.examSession('s1'), OnboardingStep.placement), isNull);
      expect(go(Routes.onboardingResult, OnboardingStep.placement), isNull);
    });

    test('after setup, only the "later" interview, level test and result are reachable', () {
      expect(go(Routes.onboardingInterview, OnboardingStep.done), Routes.home);
      expect(go(Routes.onboardingInterview, OnboardingStep.done, later: true), isNull);
      expect(go(Routes.onboardingPlacement, OnboardingStep.done, later: true), isNull);
      expect(go(Routes.onboardingResult, OnboardingStep.done, later: true), isNull);
      expect(go(Routes.onboardingProfile, OnboardingStep.done, later: true), Routes.home);
      expect(go(Routes.home, OnboardingStep.done), isNull);
      expect(go(Routes.notes, OnboardingStep.done), isNull);
    });
  });

  group('OnboardingFlow', () {
    late _FakeProfile fake;

    Future<void> pump(WidgetTester tester, Profile profile, {String start = Routes.onboardingProfile}) async {
      fake = _FakeProfile(profile);
      final container = ProviderContainer(overrides: [currentProfileProvider.overrideWith(() => fake)]);
      addTearDown(container.dispose);
      await container.read(currentProfileProvider.future);
      // No refreshListenable on purpose: the screens must move on by
      // themselves, not rely on a redirect being re-evaluated.
      final router = GoRouter(
        initialLocation: start,
        redirect: (context, state) {
          final p = container.read(currentProfileProvider).value!;
          return onboardingRedirect(
            state.matchedLocation,
            step: p.onboardingStep,
            later: state.uri.queryParameters[Routes.laterParam] == '1',
          );
        },
        routes: [
          GoRoute(path: Routes.home, builder: (_, _) => const _Step('home')),
          GoRoute(
            path: Routes.onboardingProfile,
            builder: (_, _) => const _Step('profile', next: OnboardingStep.interview),
          ),
          GoRoute(
            path: Routes.onboardingInterview,
            builder: (_, _) => const _Step('interview', next: OnboardingStep.placement),
          ),
          GoRoute(
            path: Routes.onboardingPlacement,
            builder: (_, _) => const _Step('placement', next: OnboardingStep.plan),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('"Save and continue" saves the next step and opens it', (tester) async {
      await pump(tester, const Profile(id: 'u', username: 'user_1'));
      expect(find.text('screen:profile'), findsOneWidget);

      await tester.tap(find.text('next'));
      await tester.pumpAndSettle();
      expect(find.text('screen:interview'), findsOneWidget);
      expect(fake.saves.last, {'onboarding_step': 'interview'});

      await tester.tap(find.text('next'));
      await tester.pumpAndSettle();
      expect(find.text('screen:placement'), findsOneWidget);
    });

    testWidgets('"Do it later" finishes onboarding from any step and opens Home', (tester) async {
      await pump(tester, const Profile(id: 'u', username: 'user_1', onboardingStep: OnboardingStep.interview));
      expect(find.text('screen:interview'), findsOneWidget);

      await tester.tap(find.text('later'));
      await tester.pumpAndSettle();
      expect(find.text('screen:home'), findsOneWidget);
      expect(fake.saves.single, {'onboarding_step': 'done'});
    });

    testWidgets('redone later from Home: the step stays "done" and Home opens after', (tester) async {
      await pump(
        tester,
        const Profile(id: 'u', username: 'user_1', onboardingStep: OnboardingStep.done),
        start: Routes.later(Routes.onboardingInterview),
      );
      expect(find.text('screen:interview'), findsOneWidget);

      await tester.tap(find.text('next'));
      await tester.pumpAndSettle();
      expect(find.text('screen:home'), findsOneWidget);
      expect(fake.saves, isEmpty);
    });
  });
}
