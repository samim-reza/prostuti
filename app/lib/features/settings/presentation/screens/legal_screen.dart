import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/settings/application/support.dart';
import 'package:prostuti/features/settings/presentation/widgets/settings_section.dart';

/// Date shown as "Last updated" on both documents. Keep in sync with
/// `docs/PRIVACY.md` and `docs/TERMS.md` whenever the texts change.
final legalLastUpdated = DateTime(2026, 10, 11);

typedef LegalSection = ({IconData icon, String title, String body});

enum LegalDocument {
  privacy,
  terms;

  String title(AppLocalizations l) => switch (this) {
    privacy => l.authPrivacyLink,
    terms => l.authTermsLink,
  };

  String summary(AppLocalizations l) => switch (this) {
    privacy => l.settingsAboutPrivacy,
    terms => l.settingsAboutTerms,
  };

  LegalDocument get other => this == privacy ? terms : privacy;

  /// Sections in reading order; [email] is the support address.
  List<LegalSection> sections(AppLocalizations l, String email) => switch (this) {
    privacy => [
      (icon: Icons.info_outline_rounded, title: l.settingsPrivacyWhoTitle, body: l.settingsPrivacyWho),
      (icon: Icons.badge_outlined, title: l.settingsPrivacyCollectTitle, body: l.settingsPrivacyCollect),
      (icon: Icons.insights_rounded, title: l.settingsPrivacyActivityTitle, body: l.settingsPrivacyActivity),
      (icon: Icons.phone_android_rounded, title: l.settingsPrivacyDeviceTitle, body: l.settingsPrivacyDevice),
      (icon: Icons.tune_rounded, title: l.settingsPrivacyUseTitle, body: l.settingsPrivacyUse),
      (icon: Icons.auto_awesome_outlined, title: l.settingsPrivacyAiTitle, body: l.settingsPrivacyAi),
      (icon: Icons.campaign_outlined, title: l.settingsPrivacyAdsTitle, body: l.settingsPrivacyAds),
      (icon: Icons.notifications_none_rounded, title: l.settingsPrivacyNotifTitle, body: l.settingsPrivacyNotif),
      (icon: Icons.groups_outlined, title: l.settingsPrivacySharingTitle, body: l.settingsPrivacySharing),
      (icon: Icons.lock_outline_rounded, title: l.settingsPrivacyStorageTitle, body: l.settingsPrivacyStorage),
      (icon: Icons.history_rounded, title: l.settingsPrivacyRetentionTitle, body: l.settingsPrivacyRetention),
      (icon: Icons.verified_user_outlined, title: l.settingsPrivacyChoicesTitle, body: l.settingsPrivacyChoices(email)),
      (icon: Icons.person_remove_outlined, title: l.settingsPrivacyDeleteTitle, body: l.settingsPrivacyDelete(email)),
      (icon: Icons.child_care_rounded, title: l.settingsPrivacyChildrenTitle, body: l.settingsPrivacyChildren),
      (icon: Icons.update_rounded, title: l.settingsPrivacyChangesTitle, body: l.settingsPrivacyChanges),
      (icon: Icons.mail_outline_rounded, title: l.settingsPrivacyContactTitle, body: l.settingsPrivacyContact(email)),
    ],
    terms => [
      (icon: Icons.handshake_outlined, title: l.settingsTermsAcceptTitle, body: l.settingsTermsAccept),
      (icon: Icons.account_circle_outlined, title: l.settingsTermsAccountTitle, body: l.settingsTermsAccount),
      (icon: Icons.school_outlined, title: l.settingsTermsStudyAidTitle, body: l.settingsTermsStudyAid),
      (icon: Icons.forum_outlined, title: l.settingsTermsCommunityTitle, body: l.settingsTermsCommunity),
      (icon: Icons.edit_note_rounded, title: l.settingsTermsYourContentTitle, body: l.settingsTermsYourContent),
      (icon: Icons.copyright_rounded, title: l.settingsTermsOurContentTitle, body: l.settingsTermsOurContent),
      (icon: Icons.workspace_premium_outlined, title: l.settingsTermsPlansTitle, body: l.settingsTermsPlans),
      (icon: Icons.cloud_outlined, title: l.settingsTermsAvailabilityTitle, body: l.settingsTermsAvailability),
      (icon: Icons.balance_rounded, title: l.settingsTermsLiabilityTitle, body: l.settingsTermsLiability),
      (icon: Icons.logout_rounded, title: l.settingsTermsEndTitle, body: l.settingsTermsEnd),
      (icon: Icons.gavel_rounded, title: l.settingsTermsLawTitle, body: l.settingsTermsLaw),
      (icon: Icons.update_rounded, title: l.settingsTermsChangesTitle, body: l.settingsTermsChanges),
      (icon: Icons.mail_outline_rounded, title: l.settingsTermsContactTitle, body: l.settingsTermsContact(email)),
    ],
  };
}

/// Opens the Privacy Policy or Terms of Use on top of the current screen.
/// Works signed out too (register screen), so it is not a router route.
Future<void> openLegalDocument(BuildContext context, LegalDocument document) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LegalScreen(document: document)));

class LegalScreen extends ConsumerWidget {
  const LegalScreen({required this.document, super.key});

  final LegalDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final email = ref.watch(supportEmailProvider);
    final sections = document.sections(l, email);

    return Scaffold(
      appBar: AppBar(title: Text(document.title(l))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl),
        children: [
          Text(
            l.settingsLegalUpdated(Fmt.date(legalLastUpdated, bangla: context.isBn)),
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          Gap.h12,
          Card(
            color: scheme.primaryContainer.withValues(alpha: 0.45),
            child: Padding(
              padding: Gap.card,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.settingsLegalInShort, style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary)),
                  Gap.h8,
                  Text(document.summary(l), style: theme.textTheme.bodyMedium?.copyWith(height: 1.55)),
                ],
              ),
            ),
          ),
          for (final (i, section) in sections.indexed) _SectionView(number: context.n(i + 1), section: section),
          Gap.h24,
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: const SettingsIcon(Icons.mail_outline_rounded),
                  title: Text(l.settingsContactSupport),
                  subtitle: Text(email),
                  onTap: () => unawaited(_mail(context, email, document.title(l))),
                ),
                const Divider(indent: 56),
                ListTile(
                  leading: SettingsIcon(
                    document.other == LegalDocument.terms ? Icons.gavel_rounded : Icons.privacy_tip_outlined,
                  ),
                  title: Text(
                    document.other == LegalDocument.terms ? l.settingsLegalReadTerms : l.settingsLegalReadPrivacy,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context)
                      .pushReplacement(MaterialPageRoute<void>(builder: (_) => LegalScreen(document: document.other))),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _mail(BuildContext context, String email, String subject) async {
    final ok = await launchEmail(email, subject: '${context.l10n.settingsSupportSubject} · $subject');
    if (ok || !context.mounted) return;
    await Clipboard.setData(ClipboardData(text: email));
    if (context.mounted) showInfoSnack(context, context.l10n.settingsNoMailApp(email));
  }
}

class _SectionView extends StatelessWidget {
  const _SectionView({required this.number, required this.section});

  final String number;
  final LegalSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium?.copyWith(height: 1.55, color: theme.colorScheme.onSurface);
    return Padding(
      padding: const EdgeInsets.only(top: Gap.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SettingsIcon(section.icon),
              Gap.w12,
              Expanded(child: Text('$number. ${section.title}', style: theme.textTheme.titleMedium)),
            ],
          ),
          Gap.h8,
          for (final line in section.body.split('\n'))
            if (line.startsWith('• '))
              Padding(
                padding: const EdgeInsets.only(left: Gap.xs, top: Gap.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: body),
                    Expanded(child: Text(line.substring(2), style: body)),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: Gap.xs),
                child: Text(line, style: body),
              ),
        ],
      ),
    );
  }
}
