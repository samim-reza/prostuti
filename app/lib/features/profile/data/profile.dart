import 'package:flutter/foundation.dart';
import 'package:prostuti/core/utils/json.dart';

/// Onboarding steps, in order (mirrors `profiles.onboarding_step`).
enum OnboardingStep {
  profile,
  interview,
  placement,
  plan,
  done;

  static OnboardingStep parse(String? v) =>
      OnboardingStep.values.firstWhere((e) => e.name == v, orElse: () => OnboardingStep.profile);
}

@immutable
class Profile {
  const Profile({
    required this.id,
    required this.username,
    this.fullName,
    this.avatarUrl,
    this.bio,
    this.district,
    this.education = const {},
    this.occupation,
    this.targetExams = const ['bcs'],
    this.targetScheduleId,
    this.dailyStudyMinutes = 120,
    this.onboardingStep = OnboardingStep.profile,
    this.role = 'user',
    this.reminderTime = '20:00',
    this.reminderEnabled = true,
    this.notificationSettings = const {},
    this.locale = 'bn',
    this.allowMessagesFrom = 'friends',
    this.streakCount = 0,
    this.longestStreak = 0,
    this.lastActiveDate,
    this.friendsCount = 0,
    this.postsCount = 0,
    this.examsTaken = 0,
    this.createdAt,
  });

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
    id: j.str('id'),
    username: j.str('username'),
    fullName: j.strOrNull('full_name'),
    avatarUrl: j.strOrNull('avatar_url'),
    bio: j.strOrNull('bio'),
    district: j.strOrNull('district'),
    education: j.obj('education'),
    occupation: j.strOrNull('occupation'),
    targetExams: j.strings('target_exams'),
    targetScheduleId: j.intOrNull('target_schedule_id'),
    dailyStudyMinutes: j.integer('daily_study_minutes', 120),
    onboardingStep: OnboardingStep.parse(j.strOrNull('onboarding_step')),
    role: j.str('role', 'user'),
    reminderTime: j.str('reminder_time', '20:00:00').substring(0, 5),
    reminderEnabled: j.boolean('reminder_enabled', true),
    notificationSettings: j.obj('notification_settings').map((k, v) => MapEntry(k, v == true)),
    locale: j.str('locale', 'bn'),
    allowMessagesFrom: j.str('allow_messages_from', 'friends'),
    streakCount: j.integer('streak_count'),
    longestStreak: j.integer('longest_streak'),
    lastActiveDate: j.date('last_active_date'),
    friendsCount: j.integer('friends_count'),
    postsCount: j.integer('posts_count'),
    examsTaken: j.integer('exams_taken'),
    createdAt: j.date('created_at'),
  );

  /// Columns selected from `profiles` (explicit list = smaller payloads).
  static const columns =
      'id, username, full_name, avatar_url, bio, district, education, occupation, target_exams, '
      'target_schedule_id, daily_study_minutes, onboarding_step, role, reminder_time, reminder_enabled, '
      'notification_settings, locale, allow_messages_from, streak_count, longest_streak, last_active_date, '
      'friends_count, posts_count, exams_taken, created_at';

  final String id;
  final String username;
  final String? fullName;
  final String? avatarUrl;
  final String? bio;
  final String? district;
  final Map<String, dynamic> education;
  final String? occupation;
  final List<String> targetExams;
  final int? targetScheduleId;
  final int dailyStudyMinutes;
  final OnboardingStep onboardingStep;
  final String role;
  final String reminderTime;
  final bool reminderEnabled;
  final Map<String, bool> notificationSettings;
  final String locale;
  final String allowMessagesFrom;
  final int streakCount;
  final int longestStreak;
  final DateTime? lastActiveDate;
  final int friendsCount;
  final int postsCount;
  final int examsTaken;
  final DateTime? createdAt;

  String get displayName => (fullName?.trim().isNotEmpty ?? false) ? fullName!.trim() : username;
  bool get isAdmin => role == 'admin';
  bool get isStaff => role == 'admin' || role == 'moderator';
  bool get isOnboarded => onboardingStep == OnboardingStep.done;

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'full_name': fullName,
    'avatar_url': avatarUrl,
    'bio': bio,
    'district': district,
    'education': education,
    'occupation': occupation,
    'target_exams': targetExams,
    'target_schedule_id': targetScheduleId,
    'daily_study_minutes': dailyStudyMinutes,
    'onboarding_step': onboardingStep.name,
    'role': role,
    'reminder_time': '$reminderTime:00',
    'reminder_enabled': reminderEnabled,
    'notification_settings': notificationSettings,
    'locale': locale,
    'allow_messages_from': allowMessagesFrom,
    'streak_count': streakCount,
    'longest_streak': longestStreak,
    'last_active_date': lastActiveDate?.toIso8601String(),
    'friends_count': friendsCount,
    'posts_count': postsCount,
    'exams_taken': examsTaken,
    'created_at': createdAt?.toIso8601String(),
  };
}

/// Lightweight author/user reference used in lists (feed, comments, chat…).
@immutable
class UserSummary {
  const UserSummary({required this.id, required this.username, this.fullName, this.avatarUrl});

  factory UserSummary.fromJson(Map<String, dynamic> j, {String prefix = ''}) => UserSummary(
    id: j.str('${prefix}id', j.str('${prefix}user_id')),
    username: j.str('${prefix}username'),
    fullName: j.strOrNull('${prefix}full_name'),
    avatarUrl: j.strOrNull('${prefix}avatar_url'),
  );

  final String id;
  final String username;
  final String? fullName;
  final String? avatarUrl;

  String get displayName => (fullName?.trim().isNotEmpty ?? false) ? fullName!.trim() : username;

  Map<String, dynamic> toJson() => {'id': id, 'username': username, 'full_name': fullName, 'avatar_url': avatarUrl};
}
