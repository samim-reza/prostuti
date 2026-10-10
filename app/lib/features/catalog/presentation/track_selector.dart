import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';

/// BCS · Bank · Other jobs switch shared by the question bank and model
/// tests (the choice is remembered and applies to both).
class TrackSelector extends ConsumerWidget {
  const TrackSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(examTracksProvider).value ?? ExamTrack.defaults;
    final selected = ref.watch(selectedTrackProvider);
    return Semantics(
      label: context.l10n.trackSelectorLabel,
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          segments: [
            for (final t in tracks)
              ButtonSegment(
                value: t.code,
                label: Text(t.name(context), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
          selected: {selected},
          onSelectionChanged: (s) => unawaited(ref.read(selectedTrackProvider.notifier).select(s.first)),
        ),
      ),
    );
  }
}
