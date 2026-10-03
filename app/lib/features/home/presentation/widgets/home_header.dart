import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/bd_time.dart';
import 'package:prostuti/features/home/application/home_helpers.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';

String greetingText(BuildContext context, DayPart part) {
  final l = context.l10n;
  return switch (part) {
    DayPart.dawn => l.homeGreetingDawn,
    DayPart.morning => l.homeGreetingMorning,
    DayPart.noon => l.homeGreetingNoon,
    DayPart.afternoon => l.homeGreetingAfternoon,
    DayPart.evening => l.homeGreetingEvening,
    DayPart.night => l.homeGreetingNight,
  };
}

/// "সুপ্রভাত, রহিম" — time-of-day aware (Bangladesh time).
class HomeGreeting extends ConsumerWidget {
  const HomeGreeting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final name = ref.watch(currentProfileProvider.select((p) => p.value?.displayName)) ?? '';
    final first = name.trim().split(RegExp(r'\s+')).first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          greetingText(context, dayPartFor(BdTime.now().hour)),
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        Text(
          first.isEmpty ? context.l10n.homeGreetingFallbackName : first,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge,
        ),
      ],
    );
  }
}

/// Flame + streak count; lit when the user has studied today.
class StreakChip extends ConsumerWidget {
  const StreakChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final count = ref.watch(currentProfileProvider.select((p) => p.value?.streakCount ?? 0));
    final last = ref.watch(currentProfileProvider.select((p) => p.value?.lastActiveDate));
    final today = BdTime.today();
    final streak = effectiveStreak(count: count, lastActive: last, bdToday: today);
    final lit = activeToday(lastActive: last, bdToday: today);
    final color = lit ? const Color(0xFFFF7A1A) : scheme.onSurfaceVariant;
    final l = context.l10n;
    return Tooltip(
      message: lit ? l.homeStreakTooltip(context.n(streak)) : l.homeStreakTooltipCold,
      child: Semantics(
        button: true,
        label: l.homeStreakTooltip(context.n(streak)),
        child: InkWell(
          borderRadius: Radii.chip,
          onTap: () => context.push(Routes.progress),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: Gap.md),
            decoration: BoxDecoration(
              color: (lit ? AppColors.gold : scheme.onSurfaceVariant).withValues(alpha: 0.12),
              borderRadius: Radii.chip,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_fire_department_rounded, color: color, size: 22),
                Gap.w4,
                Text(
                  context.n(streak),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
