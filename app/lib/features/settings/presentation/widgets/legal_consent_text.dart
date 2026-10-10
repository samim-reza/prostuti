import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/features/settings/presentation/screens/legal_screen.dart';

/// "I agree to the Terms of Use and Privacy Policy", with both document names
/// tappable. Word order comes from the translation, so links land in the
/// right place in Bangla and English alike.
class LegalConsentText extends StatefulWidget {
  const LegalConsentText({this.style, super.key});

  final TextStyle? style;

  @override
  State<LegalConsentText> createState() => _LegalConsentTextState();
}

class _LegalConsentTextState extends State<LegalConsentText> {
  late final _terms = TapGestureRecognizer()..onTap = () => _open(LegalDocument.terms);
  late final _privacy = TapGestureRecognizer()..onTap = () => _open(LegalDocument.privacy);

  void _open(LegalDocument document) => unawaited(openLegalDocument(context, document));

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final link = TextStyle(color: scheme.primary, fontWeight: FontWeight.w600, decoration: TextDecoration.underline);
    const termsMark = '\u0001';
    const privacyMark = '\u0002';
    return Text.rich(
      TextSpan(
        style: widget.style,
        children: spansWithLinks(l.authAgreeLegal(termsMark, privacyMark), {
          termsMark: TextSpan(text: l.authTermsLink, style: link, recognizer: _terms),
          privacyMark: TextSpan(text: l.authPrivacyLink, style: link, recognizer: _privacy),
        }),
      ),
    );
  }
}

/// Splits [template] at each key of [links] and puts the matching span there.
List<InlineSpan> spansWithLinks(String template, Map<String, InlineSpan> links) {
  if (links.isEmpty) return [TextSpan(text: template)];
  final pattern = RegExp(links.keys.map(RegExp.escape).join('|'));
  final spans = <InlineSpan>[];
  var start = 0;
  for (final match in pattern.allMatches(template)) {
    if (match.start > start) spans.add(TextSpan(text: template.substring(start, match.start)));
    spans.add(links[match[0]]!);
    start = match.end;
  }
  if (start < template.length) spans.add(TextSpan(text: template.substring(start)));
  return spans;
}
