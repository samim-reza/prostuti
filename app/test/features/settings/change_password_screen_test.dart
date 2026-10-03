import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_theme.dart';
import 'package:prostuti/features/settings/presentation/screens/change_password_screen.dart';

void main() {
  testWidgets('validates length and confirmation before calling the server', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('bn'),
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ChangePasswordScreen(),
        ),
      ),
    );
    final l = lookupAppLocalizations(const Locale('bn'));
    final fields = find.byType(TextFormField);

    await tester.enterText(fields.at(0), 'short');
    await tester.enterText(fields.at(1), 'other');
    await tester.tap(find.text(l.settingsUpdatePassword));
    await tester.pump();
    expect(find.text(l.validationPassword), findsOneWidget);
    expect(find.text(l.settingsPasswordMismatch), findsOneWidget);

    // Strength meter reacts to typing.
    await tester.enterText(fields.at(0), 'Abcdefgh12!x');
    await tester.pump();
    expect(find.text(l.settingsStrengthStrong), findsOneWidget);
  });
}
