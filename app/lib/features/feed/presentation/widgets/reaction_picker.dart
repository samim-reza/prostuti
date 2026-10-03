import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/features/feed/data/post.dart';
import 'package:prostuti/features/feed/presentation/widgets/post_labels.dart';

/// Floating pill with the six reactions, anchored above the widget that
/// owns [anchorContext]. Resolves to the picked reaction (or `null`).
Future<ReactionType?> showReactionPicker(BuildContext anchorContext, {ReactionType? current}) {
  final box = anchorContext.findRenderObject() as RenderBox?;
  final overlay = Navigator.of(anchorContext, rootNavigator: true).overlay?.context.findRenderObject() as RenderBox?;
  final anchor = (box != null && overlay != null)
      ? box.localToGlobal(Offset.zero, ancestor: overlay) & box.size
      : Rect.zero;
  return showGeneralDialog<ReactionType>(
    context: anchorContext,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(anchorContext).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (context, _, _) => _ReactionPickerLayout(anchor: anchor, current: current),
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween(begin: 0.85, end: 1.0).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutBack)),
        alignment: Alignment.bottomLeft,
        child: child,
      ),
    ),
  );
}

class _ReactionPickerLayout extends StatelessWidget {
  const _ReactionPickerLayout({required this.anchor, this.current});

  final Rect anchor;
  final ReactionType? current;

  static const _itemSize = 48.0;
  static const _height = _itemSize + Gap.sm * 2;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    const width = _itemSize * 6 + Gap.sm * 2;
    final left = anchor.left.clamp(Gap.sm, size.width - width - Gap.sm);
    var top = anchor.top - _height - Gap.sm;
    if (top < padding.top + Gap.sm) top = anchor.bottom + Gap.sm;
    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          child: Material(
            elevation: 6,
            shadowColor: Colors.black38,
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            shape: const StadiumBorder(),
            child: Padding(
              padding: const EdgeInsets.all(Gap.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [for (final r in ReactionType.values) _ReactionChoice(type: r, selected: r == current)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReactionChoice extends StatefulWidget {
  const _ReactionChoice({required this.type, required this.selected});

  final ReactionType type;
  final bool selected;

  @override
  State<_ReactionChoice> createState() => _ReactionChoiceState();
}

class _ReactionChoiceState extends State<_ReactionChoice> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.type.label(context.l10n);
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: label,
        child: InkResponse(
          onTap: () => Navigator.of(context).pop(widget.type),
          onHighlightChanged: (v) => setState(() => _hover = v),
          radius: 26,
          child: SizedBox.square(
            dimension: _ReactionPickerLayout._itemSize,
            child: Center(
              child: AnimatedScale(
                scale: _hover ? 1.35 : 1,
                duration: const Duration(milliseconds: 120),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.selected ? scheme.primary.withValues(alpha: 0.14) : Colors.transparent,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.xxs),
                    child: ExcludeSemantics(child: Text(widget.type.emoji, style: const TextStyle(fontSize: 28))),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
