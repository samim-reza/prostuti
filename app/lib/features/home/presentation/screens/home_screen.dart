import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/services/notification_service.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/home/application/home_notifications.dart';
import 'package:prostuti/features/home/application/home_providers.dart';
import 'package:prostuti/features/home/presentation/widgets/home_cards.dart';
import 'package:prostuti/features/home/presentation/widgets/home_header.dart';
import 'package:prostuti/features/home/presentation/widgets/routine_card.dart';
import 'package:prostuti/features/home/presentation/widgets/setup_card.dart';

/// The Home tab: greeting + streak, unfinished setup, exam countdown,
/// readiness, today's routine, today's notes, the daily exam and quick
/// actions.
///
/// Every section is its own small ConsumerWidget watching only its provider,
/// so a routine check-off never rebuilds the countdown or the notes. All data
/// is stale-while-revalidate from the persistent cache → instant cold start,
/// also offline.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _notificationTimer;

  @override
  void initState() {
    super.initState();
    // Local notifications follow the profile/plan; scheduled once per app run
    // and again only when the inputs change.
    ref.listenManual(homeNotificationPlanProvider, (_, plan) {
      if (plan != null) _scheduleNotifications(plan);
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _notificationTimer?.cancel();
    super.dispose();
  }

  void _scheduleNotifications(HomeNotificationPlan plan) {
    _notificationTimer?.cancel();
    // Give bootstrap's NotificationService.init() time to finish and keep the
    // first frame free of plugin work.
    _notificationTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      final l = context.l10n;
      final texts = (
        reminderTitle: l.homeReminderTitle,
        reminderBody: l.homeReminderBody,
        morningTitle: l.homeMorningTitle,
        morningBody: l.homeMorningBody,
      );
      unawaited(
        HomeNotificationScheduler(NotificationService.instance, ref.read(cacheStoreProvider)).apply(plan, texts),
      );
    });
  }

  Future<void> _refresh() async {
    final error = await refreshHome(ref.read);
    if (error != null && mounted && ConnectivityService.instance.isOnline) showErrorSnack(context, error);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        edgeOffset: kToolbarHeight + MediaQuery.paddingOf(context).top,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              floating: true,
              snap: true,
              toolbarHeight: 72,
              titleSpacing: Gap.lg,
              title: const HomeGreeting(),
              actions: [
                const StreakChip(),
                Gap.w4,
                IconButton(
                  tooltip: l.homeNotificationsTooltip,
                  onPressed: () => context.push(Routes.notifications),
                  icon: const Icon(Icons.notifications_outlined),
                ),
                IconButton(
                  tooltip: l.homeChatsTooltip,
                  onPressed: () => context.push(Routes.chats),
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                ),
                Gap.w4,
              ],
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(Gap.lg, Gap.xs, Gap.lg, Gap.xxl),
              sliver: SliverList(
                delegate: SliverChildListDelegate.fixed([
                  TrialBanner(),
                  SetupCard(),
                  CountdownCard(),
                  Gap.h12,
                  ReadinessCard(),
                  Gap.h12,
                  RoutineCard(),
                  Gap.h12,
                  NotesCard(),
                  Gap.h12,
                  DailyExamCard(),
                  Gap.h16,
                  QuickActionsGrid(),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
