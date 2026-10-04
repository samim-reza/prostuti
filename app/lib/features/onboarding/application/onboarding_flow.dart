import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/features/profile/data/profile.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';

/// The screen of each onboarding step.
String onboardingRouteFor(OnboardingStep step) => switch (step) {
  OnboardingStep.profile => Routes.onboardingProfile,
  OnboardingStep.interview => Routes.onboardingInterview,
  OnboardingStep.placement => Routes.onboardingPlacement,
  OnboardingStep.plan => Routes.onboardingResult,
  OnboardingStep.done => Routes.home,
};

/// The router's onboarding rule for a signed-in user whose profile is at
/// [step], navigating to [loc] (`later`: the `?later=1` flag): where to
/// redirect, or null to let the navigation through. Pure (unit tested).
///
/// * During onboarding only the saved step's screen is shown (plus the exam
///   screens for the level test), so saving or skipping to the next step is
///   what moves the user on.
/// * Afterwards the interview, level test and result stay reachable with
///   `?later=1` (Home's "Finish setting up"); other onboarding paths go Home.
String? onboardingRedirect(String loc, {required OnboardingStep step, required bool later}) {
  if (step != OnboardingStep.done) {
    if (loc.startsWith('/exam/')) return null;
    // Right after the level test the profile may still say "placement"
    // until it reloads; its result screen is the natural next step.
    if (loc == Routes.onboardingResult && step == OnboardingStep.placement) return null;
    final route = onboardingRouteFor(step);
    return loc == route ? null : route;
  }
  if (Routes.isOnboarding(loc)) return later && loc != Routes.onboardingProfile ? null : Routes.home;
  return null;
}

/// Moves through onboarding. No step is mandatory: each can be skipped and
/// the whole setup postponed ("Do it later"). Whatever is left stays
/// reachable from Home's "Finish setting up" card, which opens the same
/// screens in *later* mode (setup already finished or postponed).
///
/// The router only shows the step saved in the profile. These helpers save
/// first and then navigate explicitly, so screen and router always agree.
abstract final class OnboardingFlow {
  /// Setup was finished or postponed: the screen was opened again from Home.
  static bool isLater(WidgetRef ref) => ref.read(currentProfileProvider).value?.isOnboarded ?? false;

  /// The `onboarding_step` change for moving on to [next] (nothing in later
  /// mode, where the profile is already `done`).
  static Map<String, dynamic> stepPatch(WidgetRef ref, OnboardingStep next) =>
      isLater(ref) ? const {} : {'onboarding_step': next.name};

  /// Opens [next]; in later mode [laterRoute] (Home by default) instead.
  static void goNext(BuildContext context, WidgetRef ref, OnboardingStep next, {String laterRoute = Routes.home}) {
    if (!context.mounted) return;
    context.go(isLater(ref) ? laterRoute : onboardingRouteFor(next));
  }

  /// Saves [patch] together with the [next] step, then opens it.
  static Future<void> advance(
    BuildContext context,
    WidgetRef ref,
    OnboardingStep next, {
    Map<String, dynamic> patch = const {},
    String laterRoute = Routes.home,
  }) async {
    final data = {...patch, ...stepPatch(ref, next)};
    if (data.isNotEmpty) await ref.read(currentProfileProvider.notifier).save(data);
    if (context.mounted) goNext(context, ref, next, laterRoute: laterRoute);
  }

  /// "Do it later": finishes onboarding now and opens Home.
  static Future<void> finish(BuildContext context, WidgetRef ref) async {
    if (!isLater(ref)) {
      await ref.read(currentProfileProvider.notifier).save({'onboarding_step': OnboardingStep.done.name});
    }
    if (context.mounted) context.go(Routes.home);
  }
}
