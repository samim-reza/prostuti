import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/config/app_settings.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/brand.dart';

/// First-run carousel explaining the four pillars of the app.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final slides = [
      ('assets/illustrations/welcome_study.svg', l.authWelcomeTitle1, l.authWelcomeBody1),
      ('assets/illustrations/welcome_news.svg', l.authWelcomeTitle2, l.authWelcomeBody2),
      ('assets/illustrations/welcome_plan.svg', l.authWelcomeTitle3, l.authWelcomeBody3),
      ('assets/illustrations/welcome_community.svg', l.authWelcomeTitle4, l.authWelcomeBody4),
    ];
    final settings = ref.watch(appSettingsProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.sm, 0),
              child: Row(
                children: [
                  const ProstutiLogo(size: 36, showWordmark: false),
                  Gap.w8,
                  Text(l.appName, style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => unawaited(
                      ref
                          .read(appSettingsProvider.notifier)
                          .setLocale(Locale(settings.locale.languageCode == 'bn' ? 'en' : 'bn')),
                    ),
                    icon: const Icon(Icons.translate_rounded, size: 18),
                    label: Text(l.authLanguageToggle),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final (asset, title, body) = slides[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(child: SvgPicture.asset(asset, height: 240)),
                        Gap.h32,
                        Text(title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                        Gap.h12,
                        Text(
                          body,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(Gap.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(onPressed: () => context.push(Routes.register), child: Text(l.authGetStarted)),
                  Gap.h12,
                  OutlinedButton(onPressed: () => context.push(Routes.login), child: Text(l.authHaveAccount)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
