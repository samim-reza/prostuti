import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/features/profile/application/profile_edit.dart';
import 'package:prostuti/features/profile/data/bd_districts.dart';
import 'package:prostuti/features/profile/data/profile.dart';

const _profile = Profile(
  id: 'u1',
  username: 'qa_rahim',
  fullName: 'রহিম উদ্দিন',
  bio: 'বিসিএস প্রস্তুতি',
  district: 'ঢাকা',
  occupation: 'শিক্ষার্থী',
  targetExams: ['bcs', 'bank'],
  targetScheduleId: 2,
);

ProfileDraft _draft({
  String? fullName,
  String? username,
  String? bio,
  String? district = 'ঢাকা',
  String? occupation,
  List<String>? targetExams,
  int? scheduleId = 2,
  int? minutes,
  String? allow,
}) => ProfileDraft(
  fullName: fullName ?? 'রহিম উদ্দিন',
  username: username ?? 'qa_rahim',
  bio: bio ?? 'বিসিএস প্রস্তুতি',
  district: district,
  occupation: occupation ?? 'শিক্ষার্থী',
  targetExams: targetExams ?? const ['bcs', 'bank'],
  targetScheduleId: scheduleId,
  dailyStudyMinutes: minutes ?? 120,
  allowMessagesFrom: allow ?? 'friends',
);

void main() {
  group('buildProfilePatch', () {
    test('no changes → empty patch', () {
      expect(buildProfilePatch(_profile, ProfileDraft.fromProfile(_profile)), isEmpty);
      // Whitespace-only edits and reordered exams are not changes.
      expect(
        buildProfilePatch(_profile, _draft(fullName: '  রহিম উদ্দিন ', targetExams: const ['bank', 'bcs'])),
        isEmpty,
      );
    });

    test('only changed, trimmed columns; blanks become null', () {
      final patch = buildProfilePatch(
        _profile,
        _draft(fullName: '  করিম ', bio: '   ', occupation: 'চাকরিজীবী', district: null, scheduleId: null),
      );
      expect(patch, {
        'full_name': 'করিম',
        'bio': null,
        'occupation': 'চাকরিজীবী',
        'district': null,
        'target_schedule_id': null,
      });
    });

    test('username, exams, minutes and privacy', () {
      final patch = buildProfilePatch(
        _profile,
        _draft(username: ' new_name ', targetExams: const ['primary'], minutes: 5000, allow: 'everyone'),
      );
      expect(patch['username'], 'new_name');
      expect(patch['target_exams'], ['primary']);
      expect(patch['daily_study_minutes'], maxStudyMinutes);
      expect(patch['allow_messages_from'], 'everyone');
    });

    test('never sends invalid values', () {
      final patch = buildProfilePatch(_profile, _draft(targetExams: const [], allow: 'nobody', username: '  '));
      expect(patch, isEmpty);
    });

    test('only client-writable columns are ever produced', () {
      const granted = {
        'username', 'full_name', 'avatar_url', 'bio', 'district', 'education', 'occupation', 'target_exams', //
        'target_schedule_id', 'daily_study_minutes', 'onboarding_step', 'reminder_time', 'reminder_enabled',
        'notification_settings', 'locale', 'allow_messages_from',
      };
      final patch = buildProfilePatch(
        _profile,
        _draft(
          fullName: 'x',
          username: 'xyz',
          bio: 'b',
          district: 'খুলনা',
          occupation: 'o',
          targetExams: const ['bcs'],
          scheduleId: 3,
          minutes: 60,
          allow: 'everyone',
        ),
      );
      expect(granted.containsAll(patch.keys), isTrue);
    });
  });

  test('offline patch merge keeps the reminder time format', () {
    final merged = Profile.fromJson({
      ..._profile.toJson(),
      'reminder_time': '07:30:00',
      'notification_settings': const {'chat': false},
    });
    expect(merged.reminderTime, '07:30');
    expect(merged.notificationSettings['chat'], isFalse);
    expect(merged.username, 'qa_rahim');
  });

  group('districts', () {
    test('all 64 districts, unique in both languages', () {
      expect(bdDistricts, hasLength(64));
      expect(bdDistricts.map((d) => d.$1).toSet(), hasLength(64));
      expect(bdDistricts.map((d) => d.$2).toSet(), hasLength(64));
    });

    test('lookup accepts either spelling', () {
      expect(findDistrict('ঢাকা'), ('ঢাকা', 'Dhaka'));
      expect(findDistrict('  chattogram '), ('চট্টগ্রাম', 'Chattogram'));
      expect(findDistrict('Atlantis'), isNull);
      expect(districtLabel('Dhaka', bangla: true), 'ঢাকা');
      expect(districtLabel('ঢাকা', bangla: false), 'Dhaka');
      expect(districtLabel('Atlantis', bangla: true), 'Atlantis');
      expect(districtLabel('  ', bangla: true), isNull);
    });

    test('search matches both languages', () {
      expect(searchDistricts('syl').single.$1, 'সিলেট');
      expect(searchDistricts('খুল').single.$2, 'Khulna');
      expect(searchDistricts(''), hasLength(64));
    });
  });
}
