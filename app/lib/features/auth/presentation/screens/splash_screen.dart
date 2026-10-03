import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/brand.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';

/// Shown while the session's profile loads; the router moves on as soon as
/// the profile (and therefore the onboarding step) is known.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    final l = context.l10n;
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
              if (profile.hasError) ...[
                Text(l.authSplashError, style: const TextStyle(color: Colors.white)),
                Gap.h12,
                FilledButton.tonal(
                  onPressed: () => ref.invalidate(currentProfileProvider),
                  style: FilledButton.styleFrom(minimumSize: const Size(160, 44)),
                  child: Text(l.retry),
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
