import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/brand.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/settings/application/support.dart';
import 'package:prostuti/features/settings/presentation/widgets/settings_section.dart';

/// News outlets the AI pipeline reads (Bangla name, English name).
const aboutNewsSources = <(String, String)>[
  ('প্রথম আলো', 'Prothom Alo'),
  ('ইত্তেফাক', 'Ittefaq'),
  ('বাংলা ট্রিবিউন', 'Bangla Tribune'),
  ('Dhaka Tribune', 'Dhaka Tribune'),
  ('The Daily Star', 'The Daily Star'),
  ('The Business Standard', 'The Business Standard'),
  ('বাসস', 'BSS'),
  ('জাগো নিউজ', 'Jago News'),
  ('বিবিসি বাংলা', 'BBC Bangla'),
  ('BBC World', 'BBC World'),
  ('BBC Science', 'BBC Science'),
  ('Al Jazeera', 'Al Jazeera'),
  ('The Guardian', 'The Guardian'),
  ('UN News', 'UN News'),
];

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final info = ref.watch(packageInfoProvider).value;
    final version = info == null
        ? null
        : l.settingsAboutVersion(context.n(info.version), context.n(info.buildNumber.isEmpty ? '1' : info.buildNumber));
    final email = ref.watch(supportEmailProvider);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);

    return Scaffold(
      appBar: AppBar(title: Text(l.settingsAbout)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl),
        children: [
          Gap.h16,
          const Center(child: _Logo()),
          Gap.h16,
          Text(l.appName, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
          Gap.h4,
          Text(l.appTagline, style: muted, textAlign: TextAlign.center),
          if (version != null) ...[
            Gap.h12,
            Center(
              child: Chip(avatar: const Icon(Icons.verified_outlined, size: 18), label: Text(version)),
            ),
          ],
          SettingsSection(
            title: l.settingsAboutMissionTitle,
            children: [
              Padding(
                padding: Gap.card,
                child: Text(l.settingsAboutMission, style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
          SettingsSection(
            title: l.settingsAboutSourcesTitle,
            children: [
              _InfoRow(
                icon: Icons.account_balance_outlined,
                title: l.settingsAboutSyllabusTitle,
                body: l.settingsAboutSyllabus,
              ),
              _InfoRow(
                icon: Icons.newspaper_rounded,
                title: l.settingsAboutNewsTitle,
                body: l.settingsAboutNews,
                extra: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Gap.h8,
                    Wrap(
                      spacing: Gap.xs + 2,
                      runSpacing: Gap.xs + 2,
                      children: [
                        for (final (bn, en) in aboutNewsSources)
                          Chip(
                            label: Text(context.isBn ? bn : en),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                      ],
                    ),
                    Gap.h8,
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.link_rounded, size: 18, color: scheme.primary),
                        Gap.w8,
                        Expanded(
                          child: Text(
                            l.settingsAboutNewsLinkNote,
                            style: theme.textTheme.bodySmall?.copyWith(color: scheme.primary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _InfoRow(
                icon: Icons.fact_check_outlined,
                title: l.settingsAboutQuestionsTitle,
                body: l.settingsAboutQuestions,
              ),
            ],
          ),
          SettingsSection(
            title: l.settingsAboutSecurityTitle,
            children: [
              _InfoRow(
                icon: Icons.screenshot_monitor_outlined,
                title: l.secureScreenNotice,
                body: l.settingsAboutSecurity,
              ),
            ],
          ),
          SettingsSection(
            title: l.settingsAboutLegalTitle,
            children: [
              _LegalTile(
                icon: Icons.privacy_tip_outlined,
                title: l.settingsAboutPrivacyTitle,
                body: l.settingsAboutPrivacy,
              ),
              _LegalTile(icon: Icons.gavel_rounded, title: l.settingsAboutTermsTitle, body: l.settingsAboutTerms),
              ListTile(
                leading: const SettingsIcon(Icons.description_outlined),
                title: Text(l.settingsAboutLicenses),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: l.appName,
                  applicationVersion: version,
                  applicationIcon: const Padding(padding: EdgeInsets.all(Gap.sm), child: _Logo(size: 56)),
                ),
              ),
            ],
          ),
          SettingsSection(
            title: l.settingsSupport,
            children: [
              ListTile(
                leading: const SettingsIcon(Icons.mail_outline_rounded),
                title: Text(l.settingsContactSupport),
                subtitle: Text(email),
                onTap: () => unawaited(_mail(context, email, l.settingsSupportSubject)),
              ),
            ],
          ),
          Gap.h24,
          Text(
            l.settingsAboutMadeFor,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  static Future<void> _mail(BuildContext context, String email, String subject) async {
    final ok = await launchEmail(email, subject: subject);
    if (ok || !context.mounted) return;
    await Clipboard.setData(ClipboardData(text: email));
    if (context.mounted) showInfoSnack(context, context.l10n.settingsNoMailApp(email));
  }
}

/// Brand mark (core vector logo, crisp at any size and offline).
class _Logo extends StatelessWidget {
  const _Logo({this.size = 88});
  final double size;

  @override
  Widget build(BuildContext context) => ProstutiLogo(size: size, showWordmark: false);
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.title, required this.body, this.extra});

  final IconData icon;
  final String title;
  final String body;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: Gap.card,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsIcon(icon),
          Gap.w16,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                Gap.h4,
                Text(body, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ?extra,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalTile extends StatelessWidget {
  const _LegalTile({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      leading: SettingsIcon(icon),
      title: Text(title),
      shape: const Border(),
      collapsedShape: const Border(),
      childrenPadding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.lg),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(body, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))],
    );
  }
}
