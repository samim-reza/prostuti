import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';

/// Message input: multiline text, photo button, send button that is only
/// enabled when there is something to send. Rebuilds only the send button
/// on keystrokes (ValueListenableBuilder), not the screen.
class ChatComposer extends StatelessWidget {
  const ChatComposer({
    required this.controller,
    required this.onSend,
    required this.onPickImage,
    this.onChanged,
    this.focusNode,
    this.imageEnabled = true,
    super.key,
  });

  /// Matches the `messages.body` check constraint.
  static const maxLength = 4000;

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onPickImage;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;

  /// Photos need the network; the button is dimmed (but still explains why
  /// on tap) while offline.
  final bool imageEnabled;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.xs, Gap.sm, Gap.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: l.chatAttachImageTooltip,
                onPressed: onPickImage,
                icon: Icon(
                  Icons.add_photo_alternate_outlined,
                  color: imageEnabled ? scheme.primary : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: onChanged,
                  minLines: 1,
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: [LengthLimitingTextInputFormatter(maxLength)],
                  decoration: InputDecoration(
                    hintText: l.chatComposerHint,
                    isDense: true,
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radii.xl),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radii.xl),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: const BorderRadius.all(Radii.xl),
                      borderSide: BorderSide(color: scheme.primary.withValues(alpha: 0.6)),
                    ),
                  ),
                ),
              ),
              Gap.w8,
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  final enabled = value.text.trim().isNotEmpty;
                  return IconButton.filled(
                    tooltip: l.chatSendTooltip,
                    onPressed: enabled ? onSend : null,
                    style: IconButton.styleFrom(minimumSize: const Size(46, 46)),
                    icon: const Icon(Icons.send_rounded),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
