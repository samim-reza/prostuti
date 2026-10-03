import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_theme.dart';
import 'package:prostuti/features/addons/application/addons_providers.dart';
import 'package:prostuti/features/addons/data/addon_models.dart';
import 'package:prostuti/features/profile/data/profile.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';
import 'package:prostuti/features/profile/presentation/screens/my_profile_screen.dart';

class _FakeProfile extends CurrentProfileNotifier {
  _FakeProfile(this.profile);
  final Profile profile;

  @override
  Future<Profile?> build() async => profile;
}

Profile _profile({String role = 'user'}) => Profile(
  id: 'u1',
  username: 'qa_rahim',
  fullName: 'রহিম উদ্দিন',
  district: 'Dhaka',
  bio: 'বিসিএস প্রস্তুতি',
  role: role,
  friendsCount: 12,
  postsCount: 3,
  examsTaken: 27,
  streakCount: 5,
);

Widget _host(Profile p, {List<ActivePlan> plans = const []}) => ProviderScope(
  overrides: [
    currentProfileProvider.overrideWith(() => _FakeProfile(p)),
    myPlansProvider.overrideWith((ref) async => plans),
    addonCatalogProvider.overrideWith((ref) async => AddonCatalog.empty),
  ],
  child: MaterialApp(
    locale: const Locale('bn'),
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const MyProfileScreen(),
  ),
);

void main() {
  final l = lookupAppLocalizations(const Locale('bn'));

  testWidgets('renders header, Bangla stats and the free-plan card', (tester) async {
    await tester.pumpWidget(_host(_profile()));
    await tester.pumpAndSettle();
    expect(find.text('রহিম উদ্দিন'), findsOneWidget);
    expect(find.text('@qa_rahim'), findsOneWidget);
    expect(find.text('ঢাকা'), findsOneWidget); // stored in English, shown in Bangla
    expect(find.text('১২'), findsOneWidget);
    expect(find.text('২৭'), findsOneWidget);
    expect(find.text(l.profileFreePlan), findsOneWidget);
    await tester.scrollUntilVisible(find.text(l.profileMenuLogout), 200);
    expect(find.text(l.profileMenuAdmin), findsNothing);
  });

  testWidgets('staff see the admin panel entry and active plan', (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      _host(
        _profile(role: 'moderator'),
        plans: [
          ActivePlan(
            addonCode: Addon.proCode,
            source: EntitlementSource.trial,
            startsAt: now.subtract(const Duration(days: 2)),
            expiresAt: now.add(const Duration(days: 4, hours: 1)),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining(l.profileTrialRunning), findsOneWidget);
    expect(find.textContaining('৫ দিন বাকি'), findsOneWidget);
    await tester.scrollUntilVisible(find.text(l.profileMenuAdmin), 200);
    expect(find.text(l.profileMenuAdmin), findsOneWidget);
  });
}
