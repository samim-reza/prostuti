import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:prostuti/core/config/remote_config.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/brand.dart';
import 'package:url_launcher/url_launcher.dart';

final _installedVersionProvider = FutureProvider<String>((ref) async {
  try {
    return (await PackageInfo.fromPlatform()).version;
  } on Object {
    return '0.0.0';
  }
});

/// Server-controlled gates (`app_config`):
///  * `min_app_version` — blocks outdated builds with an update screen;
///  * `maintenance` — shows a banner (the app stays usable offline).
class AppGate extends ConsumerWidget {
  const AppGate({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(remoteConfigProvider).value;
    final installed = ref.watch(_installedVersionProvider).value;
    if (config == null) return child;

    if (installed != null && installed != '0.0.0' && isVersionBelow(installed, config.minAppVersion)) {
      return const _UpdateRequired();
    }
    if (config.maintenance) {
      return Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
                child: Row(
                  children: [
                    const Icon(Icons.construction_rounded, size: 18),
                    Gap.w8,
                    Expanded(
                      child: Text(
                        config.maintenanceMessage.isNotEmpty
                            ? config.maintenanceMessage
                            : context.l10n.maintenanceTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(context: context, removeTop: true, child: child),
          ),
        ],
      );
    }
    return child;
  }
}

class _UpdateRequired extends StatelessWidget {
  const _UpdateRequired();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(Gap.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ProstutiLogo(size: 80),
                Gap.h24,
                Text(l.updateRequiredTitle, style: Theme.of(context).textTheme.headlineSmall),
                Gap.h12,
                Text(l.updateRequiredBody, textAlign: TextAlign.center),
                Gap.h24,
                FilledButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse('https://github.com/samim-reza/prostuti/releases'),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.system_update_rounded),
                  label: Text(l.updateNow),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
