import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';

/// Post body that collapses after [collapsedLines] with a "See more" toggle.
/// Overflow is measured once per width with a [TextPainter], so short posts
/// never show the toggle.
class ExpandableText extends StatefulWidget {
  const ExpandableText(this.text, {this.collapsedLines = 6, this.initiallyExpanded = false, this.style, super.key});

  final String text;
  final int collapsedLines;
  final bool initiallyExpanded;
  final TextStyle? style;

  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  late bool _expanded = widget.initiallyExpanded;
  double? _measuredWidth;
  bool _overflows = false;

  bool _measure(double width, TextStyle style, TextScaler scaler, TextDirection direction) {
    if (_measuredWidth == width) return _overflows;
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: style),
      maxLines: widget.collapsedLines,
      textDirection: direction,
      textScaler: scaler,
    )..layout(maxWidth: width);
    _measuredWidth = width;
    _overflows = painter.didExceedMaxLines;
    painter.dispose();
    return _overflows;
  }

  @override
  void didUpdateWidget(ExpandableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _measuredWidth = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = widget.style ?? theme.textTheme.bodyLarge!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final overflows = _measure(
          constraints.maxWidth,
          style,
          MediaQuery.textScalerOf(context),
          Directionality.of(context),
        );
        final text = Text(
          widget.text,
          style: style,
          maxLines: _expanded || !overflows ? null : widget.collapsedLines,
          overflow: _expanded || !overflows ? TextOverflow.clip : TextOverflow.ellipsis,
        );
        if (!overflows) return text;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSize(duration: const Duration(milliseconds: 180), alignment: Alignment.topCenter, child: text),
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 32),
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: 1,
                  child: Text(
                    _expanded ? context.l10n.feedSeeLess : context.l10n.feedSeeMore,
                    style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
