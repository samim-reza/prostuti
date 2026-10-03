import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/feed/l10n/social_failures.dart';
import 'package:prostuti/features/friends/application/relationship_controller.dart';
import 'package:prostuti/features/friends/data/friends_repository.dart';
import 'package:prostuti/features/friends/data/relationship.dart';

/// Opens (or creates) the 1:1 chat with [userId]. Needs the network.
Future<void> openDirectChat(BuildContext context, WidgetRef ref, String userId) async {
  if (!ensureOnline(context)) return;
  final repo = ref.read(friendsRepositoryProvider);
  final router = GoRouter.of(context);
  try {
    final id = await repo.openDirectConversation(userId);
    unawaited(router.push(Routes.chat(id)));
  } on Object catch (e) {
    if (context.mounted) showSocialError(context, e);
  }
}

/// Relationship-aware action button(s): add friend → request sent (cancel)
/// → confirm/delete → friends (message / unfriend) → blocked (unblock).
/// Every action is optimistic; accepting/declining also works offline.
class RelationshipButton extends ConsumerStatefulWidget {
  const RelationshipButton({required this.userId, required this.displayName, this.expanded = false, super.key});

  final String userId;
  final String displayName;

  /// Full-width profile layout (otherwise a compact trailing button).
  final bool expanded;

  @override
  ConsumerState<RelationshipButton> createState() => _RelationshipButtonState();
}

class _RelationshipButtonState extends ConsumerState<RelationshipButton> {
  bool _busy = false;

  Future<void> _run(
    Future<void> Function(RelationshipNotifier n) action, {
    bool needsNetwork = true,
    String? success,
  }) async {
    if (_busy || (needsNetwork && !ensureOnline(context))) return;
    final notifier = ref.read(relationshipProvider(widget.userId).notifier);
    setState(() => _busy = true);
    try {
      await action(notifier);
      if (success != null && mounted) showInfoSnack(context, success);
    } on Object catch (e) {
      if (mounted) showSocialError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unfriend() async {
    final l = context.l10n;
    final ok = await confirmDialog(
      context,
      title: l.friendsUnfriendConfirmTitle(widget.displayName),
      message: l.friendsUnfriendConfirmBody,
      confirmLabel: l.friendsUnfriend,
      destructive: true,
    );
    if (ok && mounted) await _run((n) => n.unfriend(), success: l.friendsUnfriended);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final rel = ref.watch(relationshipProvider(widget.userId));
    return rel.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => _sized(
        const OutlinedButton(
          onPressed: null,
          child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
      error: (_, _) => IconButton(
        tooltip: l.retry,
        icon: const Icon(Icons.refresh_rounded),
        onPressed: () => ref.invalidate(relationshipProvider(widget.userId)),
      ),
      data: (r) => IgnorePointer(ignoring: _busy, child: _forStatus(r)),
    );
  }

  Widget _sized(Widget child) => widget.expanded ? SizedBox(width: double.infinity, child: child) : child;

  Widget _forStatus(Relationship r) {
    final l = context.l10n;
    switch (r.status) {
      case RelationshipStatus.self:
        return const SizedBox.shrink();
      case RelationshipStatus.none:
        return _sized(
          FilledButton.icon(
            onPressed: () => unawaited(_run((n) => n.sendRequest())),
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: Text(l.friendsAddFriend),
          ),
        );
      case RelationshipStatus.requestSent:
        if (!widget.expanded) {
          return OutlinedButton.icon(
            onPressed: () => unawaited(_run((n) => n.cancelRequest(), success: l.friendsRequestCancelled)),
            icon: const Icon(Icons.close_rounded, size: 18),
            label: Text(l.friendsCancelRequest),
          );
        }
        return _MenuButton(
          icon: Icons.schedule_send_rounded,
          label: l.friendsRequestSent,
          items: [
            (
              icon: Icons.close_rounded,
              label: l.friendsCancelRequest,
              onTap: () => unawaited(_run((n) => n.cancelRequest(), success: l.friendsRequestCancelled)),
            ),
          ],
        );
      case RelationshipStatus.requestReceived:
        void accept() => unawaited(_run((n) => n.accept(), needsNetwork: false, success: l.friendsAccepted));
        void decline() => unawaited(_run((n) => n.decline(), needsNetwork: false, success: l.friendsDeclined));
        if (!widget.expanded) {
          // Narrow trailing slot: one "Respond" button with both choices.
          return _MenuButton(
            icon: Icons.person_add_alt_1_rounded,
            label: l.friendsRespond,
            tonal: true,
            fullWidth: false,
            items: [
              (icon: Icons.check_rounded, label: l.friendsAccept, onTap: accept),
              (icon: Icons.close_rounded, label: l.friendsDecline, onTap: decline),
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: FilledButton(onPressed: accept, child: Text(l.friendsAccept)),
            ),
            Gap.w8,
            Expanded(
              child: OutlinedButton(onPressed: decline, child: Text(l.friendsDecline)),
            ),
          ],
        );
      case RelationshipStatus.friends:
        return _MenuButton(
          icon: Icons.how_to_reg_rounded,
          label: l.friendsIsFriend,
          tonal: true,
          fullWidth: widget.expanded,
          items: [
            (
              icon: Icons.chat_bubble_outline_rounded,
              label: l.friendsMessage,
              onTap: () => unawaited(openDirectChat(context, ref, widget.userId)),
            ),
            (icon: Icons.person_remove_outlined, label: l.friendsUnfriend, onTap: () => unawaited(_unfriend())),
          ],
        );
      case RelationshipStatus.blocked:
        return _sized(
          OutlinedButton.icon(
            onPressed: () => unawaited(_run((n) => n.unblock(), success: l.friendsUnblocked)),
            icon: const Icon(Icons.block_rounded, size: 18),
            label: Text(l.friendsUnblock),
          ),
        );
    }
  }
}

typedef _MenuItem = ({IconData icon, String label, VoidCallback onTap});

/// A button that opens a small menu of follow-up actions.
class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.icon,
    required this.label,
    required this.items,
    this.tonal = false,
    this.fullWidth = true,
  });

  final IconData icon;
  final String label;
  final List<_MenuItem> items;
  final bool tonal;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (final item in items)
          MenuItemButton(leadingIcon: Icon(item.icon), onPressed: item.onTap, child: Text(item.label)),
      ],
      builder: (context, controller, _) {
        void toggle() => controller.isOpen ? controller.close() : controller.open();
        final content = Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18),
            Gap.w8,
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            const Icon(Icons.arrow_drop_down_rounded, size: 20),
          ],
        );
        final button = tonal
            ? FilledButton.tonal(onPressed: toggle, child: content)
            : OutlinedButton(onPressed: toggle, child: content);
        return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
      },
    );
  }
}
