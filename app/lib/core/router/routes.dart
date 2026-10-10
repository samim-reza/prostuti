/// Every route path in the app, in one place. Screens navigate with
/// `context.push(Routes.postDetail(id))` instead of hard-coded strings.
abstract final class Routes {
  // Entry & auth
  static const splash = '/splash';
  static const welcome = '/welcome';
  static const login = '/auth/login';
  static const register = '/auth/register';
  static const forgotPassword = '/auth/forgot';
  static const resetPassword = '/auth/reset';

  // Onboarding
  static const onboardingProfile = '/onboarding/profile';
  static const onboardingInterview = '/onboarding/interview';
  static const onboardingPlacement = '/onboarding/placement';
  static const onboardingResult = '/onboarding/result';

  /// The interview, level test or result opened again from Home after setup
  /// was finished or postponed (only these pass the router's onboarding gate).
  static String later(String onboardingRoute) => '$onboardingRoute?$laterParam=1';
  static const laterParam = 'later';

  // Bottom-navigation tabs
  static const home = '/home';
  static const study = '/study';
  static const exams = '/exams';
  static const community = '/community';
  static const profile = '/profile';

  // Current affairs
  static const notes = '/notes';
  static const dailyExam = '/daily-exam';
  static const leaderboard = '/leaderboard';

  // Exams
  static String examSession(String sessionId) => '/exam/$sessionId';
  static String examResult(String sessionId) => '/exam/$sessionId/result';
  static String examReview(String sessionId) => '/exam/$sessionId/review';
  static const examHistory = '/exams/history';
  static const modelTests = '/exams/model-tests';

  // Question bank & practice
  static const questionBank = '/question-bank';

  /// [track]: the question-bank section the subject was opened from.
  static String subjectDetail(int subjectId, {String? track}) =>
      '/question-bank/subject/$subjectId${track == null ? '' : '?track=$track'}';

  /// [track] limits practice to one exam section's questions (question
  /// bank); without it every question qualifies (plan items, search…).
  static String practice({int? subjectId, int? topicId, int? sourceId, String? track}) {
    final q = <String>[
      if (subjectId != null) 'subject=$subjectId',
      if (topicId != null) 'topic=$topicId',
      if (sourceId != null) 'source=$sourceId',
      if (track != null) 'track=$track',
    ].join('&');
    return '/practice${q.isEmpty ? '' : '?$q'}';
  }

  static const wrongAnswers = '/wrong-answers';
  static const bookmarks = '/bookmarks';

  // Study plan & progress
  static const plan = '/plan';
  static String planDay(int dayId) => '/plan/day/$dayId';
  static const progress = '/progress';

  // Community
  static const composePost = '/post/new';
  static String postDetail(String postId) => '/post/$postId';
  static String userProfile(String userId) => '/user/$userId';
  static const friends = '/friends';
  static const userSearch = '/friends/search';
  static const chats = '/chats';
  static String chat(String conversationId) => '/chats/$conversationId';
  static const newGroup = '/chats/new-group';

  // Account
  static const notifications = '/notifications';
  static const addons = '/addons';
  static const settings = '/settings';
  static const editProfile = '/settings/profile';
  static const reminders = '/settings/reminders';
  static const changePassword = '/settings/password';
  static const blockedUsers = '/settings/blocked';
  static const about = '/settings/about';

  // Admin (role-gated)
  static const admin = '/admin';
  static const adminQuestions = '/admin/questions';
  static const adminReports = '/admin/reports';
  static const adminSchedules = '/admin/schedules';

  /// Routes reachable without a session.
  static const public = {splash, welcome, login, register, forgotPassword, resetPassword};

  static bool isOnboarding(String location) => location.startsWith('/onboarding');
}
