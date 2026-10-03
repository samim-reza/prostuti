import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/router/shell_scaffold.dart';
import 'package:prostuti/features/addons/presentation/screens/addons_screen.dart';
import 'package:prostuti/features/admin/presentation/screens/admin_dashboard_screen.dart';
import 'package:prostuti/features/admin/presentation/screens/admin_questions_screen.dart';
import 'package:prostuti/features/admin/presentation/screens/admin_reports_screen.dart';
import 'package:prostuti/features/admin/presentation/screens/admin_schedules_screen.dart';
import 'package:prostuti/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:prostuti/features/auth/presentation/screens/login_screen.dart';
import 'package:prostuti/features/auth/presentation/screens/register_screen.dart';
import 'package:prostuti/features/auth/presentation/screens/reset_password_screen.dart';
import 'package:prostuti/features/auth/presentation/screens/splash_screen.dart';
import 'package:prostuti/features/auth/presentation/screens/welcome_screen.dart';
import 'package:prostuti/features/bookmarks/presentation/screens/bookmarks_screen.dart';
import 'package:prostuti/features/chat/presentation/screens/chat_list_screen.dart';
import 'package:prostuti/features/chat/presentation/screens/chat_thread_screen.dart';
import 'package:prostuti/features/chat/presentation/screens/new_group_screen.dart';
import 'package:prostuti/features/daily_exam/presentation/screens/daily_exam_screen.dart';
import 'package:prostuti/features/daily_exam/presentation/screens/leaderboard_screen.dart';
import 'package:prostuti/features/daily_notes/presentation/screens/daily_notes_screen.dart';
import 'package:prostuti/features/exam/presentation/screens/exam_history_screen.dart';
import 'package:prostuti/features/exam/presentation/screens/exam_result_screen.dart';
import 'package:prostuti/features/exam/presentation/screens/exam_review_screen.dart';
import 'package:prostuti/features/exam/presentation/screens/exam_session_screen.dart';
import 'package:prostuti/features/exam/presentation/screens/exams_screen.dart';
import 'package:prostuti/features/exam/presentation/screens/model_tests_screen.dart';
import 'package:prostuti/features/feed/presentation/screens/community_screen.dart';
import 'package:prostuti/features/feed/presentation/screens/compose_post_screen.dart';
import 'package:prostuti/features/feed/presentation/screens/post_detail_screen.dart';
import 'package:prostuti/features/friends/presentation/screens/friends_screen.dart';
import 'package:prostuti/features/friends/presentation/screens/user_profile_screen.dart';
import 'package:prostuti/features/friends/presentation/screens/user_search_screen.dart';
import 'package:prostuti/features/home/presentation/screens/home_screen.dart';
import 'package:prostuti/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:prostuti/features/onboarding/presentation/screens/onboarding_interview_screen.dart';
import 'package:prostuti/features/onboarding/presentation/screens/onboarding_placement_screen.dart';
import 'package:prostuti/features/onboarding/presentation/screens/onboarding_profile_screen.dart';
import 'package:prostuti/features/onboarding/presentation/screens/onboarding_result_screen.dart';
import 'package:prostuti/features/profile/data/profile.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';
import 'package:prostuti/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:prostuti/features/profile/presentation/screens/my_profile_screen.dart';
import 'package:prostuti/features/question_bank/presentation/screens/practice_screen.dart';
import 'package:prostuti/features/question_bank/presentation/screens/previous_year_screen.dart';
import 'package:prostuti/features/question_bank/presentation/screens/question_bank_screen.dart';
import 'package:prostuti/features/question_bank/presentation/screens/subject_detail_screen.dart';
import 'package:prostuti/features/question_bank/presentation/screens/wrong_answers_screen.dart';
import 'package:prostuti/features/settings/presentation/screens/about_screen.dart';
import 'package:prostuti/features/settings/presentation/screens/blocked_users_screen.dart';
import 'package:prostuti/features/settings/presentation/screens/change_password_screen.dart';
import 'package:prostuti/features/settings/presentation/screens/reminder_settings_screen.dart';
import 'package:prostuti/features/settings/presentation/screens/settings_screen.dart';
import 'package:prostuti/features/study/presentation/screens/study_screen.dart';
import 'package:prostuti/features/study_plan/presentation/screens/plan_day_screen.dart';
import 'package:prostuti/features/study_plan/presentation/screens/progress_screen.dart';
import 'package:prostuti/features/study_plan/presentation/screens/study_plan_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Bridges Riverpod state (session + profile) to GoRouter's
/// `refreshListenable`, so redirects re-run on sign-in/out and when the
/// onboarding step changes — without rebuilding the router itself.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref
      ..listen(authStateProvider, (_, _) => notifyListeners())
      ..listen(currentProfileProvider.select((p) => p.value?.onboardingStep), (_, _) => notifyListeners())
      ..listen(currentProfileProvider.select((p) => p.hasValue), (_, _) => notifyListeners());
  }
}

String _onboardingRoute(OnboardingStep step) => switch (step) {
  OnboardingStep.profile => Routes.onboardingProfile,
  OnboardingStep.interview => Routes.onboardingInterview,
  OnboardingStep.placement => Routes.onboardingPlacement,
  OnboardingStep.plan => Routes.onboardingResult,
  OnboardingStep.done => Routes.home,
};

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final signedIn = ref.read(supabaseProvider).auth.currentSession != null;

      if (!signedIn) {
        if (loc == Routes.splash || !Routes.public.contains(loc)) return Routes.welcome;
        return null;
      }

      // Password-recovery deep link: let the user set a new password first.
      if (loc == Routes.resetPassword) return null;

      final profile = ref.read(currentProfileProvider);
      if (!profile.hasValue) return loc == Routes.splash ? null : Routes.splash;
      final p = profile.value;
      if (p == null) return loc == Routes.splash ? null : Routes.splash;

      if (!p.isOnboarded) {
        // The placement test runs inside the regular exam screens.
        if (Routes.isOnboarding(loc) || loc.startsWith('/exam/')) return null;
        return _onboardingRoute(p.onboardingStep);
      }
      if (loc == Routes.splash || Routes.public.contains(loc) || Routes.isOnboarding(loc)) {
        return Routes.home;
      }
      if (loc.startsWith('/admin') && !p.isStaff) return Routes.home;
      return null;
    },
    errorBuilder: (context, state) => const SplashScreen(),
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.register, builder: (_, _) => const RegisterScreen()),
      GoRoute(path: Routes.forgotPassword, builder: (_, _) => const ForgotPasswordScreen()),
      GoRoute(path: Routes.resetPassword, builder: (_, _) => const ResetPasswordScreen()),

      GoRoute(path: Routes.onboardingProfile, builder: (_, _) => const OnboardingProfileScreen()),
      GoRoute(path: Routes.onboardingInterview, builder: (_, _) => const OnboardingInterviewScreen()),
      GoRoute(path: Routes.onboardingPlacement, builder: (_, _) => const OnboardingPlacementScreen()),
      GoRoute(path: Routes.onboardingResult, builder: (_, _) => const OnboardingResultScreen()),

      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => ShellScaffold(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.study, builder: (_, _) => const StudyScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.exams, builder: (_, _) => const ExamsScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.community, builder: (_, _) => const CommunityScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.profile, builder: (_, _) => const MyProfileScreen())],
          ),
        ],
      ),

      // Current affairs
      GoRoute(path: Routes.notes, builder: (_, _) => const DailyNotesScreen()),
      GoRoute(path: Routes.dailyExam, builder: (_, _) => const DailyExamScreen()),
      GoRoute(path: Routes.leaderboard, builder: (_, _) => const LeaderboardScreen()),

      // Exams
      GoRoute(path: Routes.examHistory, builder: (_, _) => const ExamHistoryScreen()),
      GoRoute(path: Routes.modelTests, builder: (_, _) => const ModelTestsScreen()),
      GoRoute(
        path: '/exam/:id',
        builder: (_, s) => ExamSessionScreen(sessionId: s.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'result',
            builder: (_, s) => ExamResultScreen(sessionId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: 'review',
            builder: (_, s) => ExamReviewScreen(sessionId: s.pathParameters['id']!),
          ),
        ],
      ),

      // Question bank
      GoRoute(path: Routes.questionBank, builder: (_, _) => const QuestionBankScreen()),
      GoRoute(path: Routes.previousYear, builder: (_, _) => const PreviousYearScreen()),
      GoRoute(
        path: '/question-bank/subject/:id',
        builder: (_, s) => SubjectDetailScreen(subjectId: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/practice',
        builder: (_, s) => PracticeScreen(
          subjectId: int.tryParse(s.uri.queryParameters['subject'] ?? ''),
          topicId: int.tryParse(s.uri.queryParameters['topic'] ?? ''),
          sourceId: int.tryParse(s.uri.queryParameters['source'] ?? ''),
        ),
      ),
      GoRoute(path: Routes.wrongAnswers, builder: (_, _) => const WrongAnswersScreen()),
      GoRoute(path: Routes.bookmarks, builder: (_, _) => const BookmarksScreen()),

      // Plan & progress
      GoRoute(path: Routes.plan, builder: (_, _) => const StudyPlanScreen()),
      GoRoute(
        path: '/plan/day/:id',
        builder: (_, s) => PlanDayScreen(dayId: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(path: Routes.progress, builder: (_, _) => const ProgressScreen()),

      // Community
      GoRoute(path: Routes.composePost, builder: (_, _) => const ComposePostScreen()),
      GoRoute(
        path: '/post/:id',
        builder: (_, s) => PostDetailScreen(postId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/user/:id',
        builder: (_, s) => UserProfileScreen(userId: s.pathParameters['id']!),
      ),
      GoRoute(path: Routes.friends, builder: (_, _) => const FriendsScreen()),
      GoRoute(path: Routes.userSearch, builder: (_, _) => const UserSearchScreen()),
      GoRoute(path: Routes.chats, builder: (_, _) => const ChatListScreen()),
      GoRoute(path: Routes.newGroup, builder: (_, _) => const NewGroupScreen()),
      GoRoute(
        path: '/chats/:id',
        builder: (_, s) => ChatThreadScreen(conversationId: s.pathParameters['id']!),
      ),

      // Account
      GoRoute(path: Routes.notifications, builder: (_, _) => const NotificationsScreen()),
      GoRoute(path: Routes.addons, builder: (_, _) => const AddonsScreen()),
      GoRoute(path: Routes.settings, builder: (_, _) => const SettingsScreen()),
      GoRoute(path: Routes.editProfile, builder: (_, _) => const EditProfileScreen()),
      GoRoute(path: Routes.reminders, builder: (_, _) => const ReminderSettingsScreen()),
      GoRoute(path: Routes.changePassword, builder: (_, _) => const ChangePasswordScreen()),
      GoRoute(path: Routes.blockedUsers, builder: (_, _) => const BlockedUsersScreen()),
      GoRoute(path: Routes.about, builder: (_, _) => const AboutScreen()),

      // Admin
      GoRoute(path: Routes.admin, builder: (_, _) => const AdminDashboardScreen()),
      GoRoute(path: Routes.adminQuestions, builder: (_, _) => const AdminQuestionsScreen()),
      GoRoute(path: Routes.adminReports, builder: (_, _) => const AdminReportsScreen()),
      GoRoute(path: Routes.adminSchedules, builder: (_, _) => const AdminSchedulesScreen()),
    ],
  );
});
