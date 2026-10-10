import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:prostuti/core/config/app_constants.dart';
import 'package:prostuti/core/config/remote_config.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_theme.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/features/settings/application/support.dart';
import 'package:prostuti/features/settings/presentation/screens/about_screen.dart';
import 'package:prostuti/features/settings/presentation/screens/legal_screen.dart';
import 'package:prostuti/features/settings/presentation/widgets/legal_consent_text.dart';

Widget _host(Widget child, {Locale locale = const Locale('bn')}) => ProviderScope(
  overrides: [
    remoteConfigProvider.overrideWith((ref) async => RemoteConfig.fallback),
    packageInfoProvider.overrideWith(
      (ref) async =>
          PackageInfo(appName: 'Prostuti', packageName: 'io.prostuti.app', version: '1.0.0', buildNumber: '7'),
    ),
  ],
  child: MaterialApp(
    locale: locale,
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('bn');
    await initializeDateFormatting('en');
  });

  group('spansWithLinks', () {
    String render(List<InlineSpan> spans) => spans.map((s) => (s as TextSpan).text).join('|');
    final links = {'\u0001': const TextSpan(text: 'T'), '\u0002': const TextSpan(text: 'P')};

    test('places links where the translation puts them', () {
      expect(render(spansWithLinks('I agree to the \u0001 and \u0002', links)), 'I agree to the |T| and |P');
      expect(render(spansWithLinks('আমি \u0001 ও \u0002তে সম্মত', links)), 'আমি |T| ও |P|তে সম্মত');
      expect(render(spansWithLinks('\u0002 first', links)), 'P| first');
    });

    test('text without markers stays one span', () {
      expect(render(spansWithLinks('plain', links)), 'plain');
      expect(render(spansWithLinks('plain', const {})), 'plain');
    });
  });

  for (final locale in const [Locale('bn'), Locale('en')]) {
    for (final document in LegalDocument.values) {
      testWidgets('${document.name} renders every section (${locale.languageCode})', (tester) async {
        await tester.pumpWidget(_host(LegalScreen(document: document), locale: locale));
        await tester.pumpAndSettle();
        final l = lookupAppLocalizations(locale);
        final sections = document.sections(l, AppConstants.supportEmail);
        expect(find.text(document.title(l)), findsOneWidget);
        expect(find.text(l.settingsLegalInShort), findsOneWidget);
        expect(sections.length, greaterThanOrEqualTo(12));
        for (final s in sections) {
          expect(s.title.trim(), isNotEmpty);
          expect(s.body.trim(), isNotEmpty);
          expect(s.body, isNot(contains('{')), reason: 'unfilled placeholder in ${s.title}');
        }
        // Last section and the contact card are reachable.
        final bangla = locale.languageCode == 'bn';
        await tester.scrollUntilVisible(
          find.text('${Fmt.digits(sections.length, bangla: bangla)}. ${sections.last.title}'),
          400,
        );
        await tester.scrollUntilVisible(find.text(AppConstants.supportEmail), 400);
        expect(find.text(AppConstants.supportEmail), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final locale in const [Locale('bn'), Locale('en')]) {
    test('privacy policy names the processors and the deletion path (${locale.languageCode})', () {
      final l = lookupAppLocalizations(locale);
      final text = LegalDocument.privacy.sections(l, 'help@example.org').map((s) => '${s.title}\n${s.body}').join('\n');
      for (final word in ['Supabase', 'ap-south-1', 'OpenAI', 'AdMob', 'advertising ID', 'help@example.org']) {
        expect(text, contains(word));
      }
      expect(text, contains(l.settingsDeleteAccount));
    });
  }

  testWidgets('the other document is one tap away', (tester) async {
    final l = lookupAppLocalizations(const Locale('en'));
    await tester.pumpWidget(_host(const LegalScreen(document: LegalDocument.privacy), locale: const Locale('en')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(l.settingsLegalReadTerms), 400);
    await tester.tap(find.text(l.settingsLegalReadTerms));
    await tester.pumpAndSettle();
    expect(find.byType(LegalScreen), findsOneWidget); // replaced, not stacked
    expect(find.text('1. ${l.settingsTermsAcceptTitle}'), findsOneWidget);
  });

  testWidgets('about screen opens the full privacy policy', (tester) async {
    final l = lookupAppLocalizations(const Locale('bn'));
    await tester.pumpWidget(_host(const AboutScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(l.settingsAboutPrivacyHint), 300);
    await tester.tap(find.text(l.settingsAboutPrivacyHint));
    await tester.pumpAndSettle();
    expect(find.byType(LegalScreen), findsOneWidget);
    expect(find.text(l.settingsLegalInShort), findsOneWidget);
  });

  for (final locale in const [Locale('bn'), Locale('en')]) {
    testWidgets('consent line links open the documents (${locale.languageCode})', (tester) async {
      final l = lookupAppLocalizations(locale);
      await tester.pumpWidget(_host(const LegalConsentText(), locale: locale));
      await tester.pumpAndSettle();

      await tester.tapOnText(find.textRange.ofSubstring(l.authTermsLink));
      await tester.pumpAndSettle();
      expect(tester.widget<LegalScreen>(find.byType(LegalScreen)).document, LegalDocument.terms);

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      await tester.tapOnText(find.textRange.ofSubstring(l.authPrivacyLink));
      await tester.pumpAndSettle();
      expect(tester.widget<LegalScreen>(find.byType(LegalScreen)).document, LegalDocument.privacy);
    });
  }
}
