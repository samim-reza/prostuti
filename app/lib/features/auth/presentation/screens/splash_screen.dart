import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/brand.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';
import 'package:prostuti/features/settings/presentation/logout.dart';

/// Shown while the session's profile loads; the router moves on as soon as
/// the profile (and therefore the onboarding step) is known.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      // Forced past the cache, which remembers a missing profile for a while.
      await ref.read(currentProfileProvider.notifier).reload();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider);
    final signedIn = ref.watch(currentUserIdProvider) != null;
    final l = context.l10n;
    // The router waits here until there is a profile, so a failed load or a
    // signed-in account without a profile row needs a way out.
    final stuck = !_retrying && !profile.isLoading && (profile.hasError || (signedIn && profile.value == null));
    return Scaffold(
      backgroundColor: AppColors.brand,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ProstutiLogo(size: 96, onDark: true),
              Gap.h8,
              Text(
                l.appTagline,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              Gap.h32,
              if (stuck) ...[
                Text(l.authSplashError, style: const TextStyle(color: Colors.white)),
                Gap.h12,
                FilledButton.tonal(
                  onPressed: () => unawaited(_retry()),
                  style: FilledButton.styleFrom(minimumSize: const Size(160, 44)),
                  child: Text(l.retry),
                ),
                Gap.h8,
                TextButton(
                  onPressed: () => unawaited(confirmAndSignOut(context, ref)),
                  style: TextButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size(160, 44)),
                  child: Text(l.authSignOut),
                ),
              ] else
                const SizedBox.square(
                  dimension: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
