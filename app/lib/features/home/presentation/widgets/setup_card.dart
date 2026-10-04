import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/features/home/presentation/widgets/home_card.dart';
import 'package:prostuti/features/onboarding/data/onboarding_repository.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';

/// "Hide" on the setup card, remembered per user on this device.
class SetupCardHiddenNotifier extends Notifier<bool> {
  static String _key(String uid) => 'home:setup_hidden:$uid';

  @override
  bool build() {
    final uid = ref.watch(currentUserIdProvider);
    return uid != null && ref.read(cacheStoreProvider).read(_key(uid))?.data == true;
  }

  Future<void> hide() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    state = true;
    await ref.read(cacheStoreProvider).write(_key(uid), true, const Duration(days: 3650));
  }
}

final setupCardHiddenProvider = NotifierProvider<SetupCardHiddenNotifier, bool>(SetupCardHiddenNotifier.new);

/// Onboarding is optional: whatever the user skipped (profile details, the
/// AI interview, the level test) is offered here until done or hidden.
class SetupCard extends ConsumerWidget {
  const SetupCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider).value;
    final status = ref.watch(setupStatusProvider).value;
    final hidden = ref.watch(setupCardHiddenProvider);
    if (profile == null || !profile.isOnboarded || status == null || hidden) return const SizedBox.shrink();

    final l = context.l10n;
    final items = [
      if ((profile.district ?? '').isEmpty) (Icons.person_outline_rounded, l.homeSetupProfile, Routes.editProfile),
      if (!status.interviewDone) (Icons.forum_outlined, l.homeSetupInterview, Routes.later(Routes.onboardingInterview)),
      if (!status.placementDone)
        (Icons.fact_check_outlined, l.homeSetupPlacement, Routes.later(Routes.onboardingPlacement)),
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: HomeCard(
        title: l.homeSetupTitle,
        icon: Icons.checklist_rounded,
        trailing: TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 36)),
          onPressed: () => unawaited(ref.read(setupCardHiddenProvider.notifier).hide()),
          child: Text(l.homeSetupHide),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.homeSetupBody, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            Gap.h4,
            for (final (icon, label, route) in items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(icon, color: scheme.primary),
                title: Text(label),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(route),
              ),
          ],
        ),
      ),
    );
  }
}
