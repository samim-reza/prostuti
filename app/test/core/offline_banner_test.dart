import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/offline/offline_banner.dart';

/// Same shape as the real app: the banner wraps the router's Navigator in
/// `MaterialApp.builder`.
Widget _app() => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => OfflineBanner(child: child!),
  home: const Scaffold(body: Text('page')),
);

void main() {
  tearDown(ConnectivityService.instance.reportSuccess);

  testWidgets('hidden while online', (tester) async {
    ConnectivityService.instance.reportSuccess();
    await tester.pumpWidget(_app());
    expect(find.text('page'), findsOneWidget);
    expect(find.textContaining("You're offline"), findsNothing);
  });

  testWidgets('shown (and announced) while offline', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app());
    ConnectivityService.instance.reportFailure();
    await tester.pumpAndSettle();
    expect(find.textContaining("You're offline"), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp("You're offline")), findsOneWidget);
    expect(find.text('page'), findsOneWidget);
    semantics.dispose();
  });
}
