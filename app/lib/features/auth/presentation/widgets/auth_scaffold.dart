import 'package:flutter/material.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/brand.dart';

/// Shared layout for the sign-in / sign-up / reset screens: brand mark,
/// title, subtitle and a scrollable, keyboard-safe form area.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({required this.title, required this.child, this.subtitle, this.showBack = true, super.key});

  final String title;
  final String? subtitle;
  final Widget child;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: showBack),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: ProstutiLogo(size: 64, showWordmark: false)),
                    Gap.h24,
                    Text(title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                    if (subtitle != null) ...[
                      Gap.h8,
                      Text(
                        subtitle!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                    Gap.h24,
                    child,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Password field with a visibility toggle.
class PasswordField extends StatefulWidget {
  const PasswordField({
    required this.controller,
    required this.label,
    this.validator,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
    this.autofillHints = const [AutofillHints.password],
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String> autofillHints;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      validator: widget.validator,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onSubmitted,
      autofillHints: widget.autofillHints,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.lock_outline_rounded),
        suffixIcon: IconButton(
          tooltip: widget.label,
          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}

/// Maps validator codes (core `Validators`) to localized messages.
String? validationMessage(BuildContext context, String? code) {
  if (code == null) return null;
  final l = context.l10n;
  return switch (code) {
    'required' => l.validationRequired,
    'invalid_email' => l.validationEmail,
    'password_too_short' => l.validationPassword,
    'invalid_username' => l.validationUsername,
    _ => l.validationRequired,
  };
}

/// Auth-specific error text (wrong password, existing account …).
String authErrorMessage(BuildContext context, Object error) {
  final l = context.l10n;
  final text = error.toString().toLowerCase();
  if (text.contains('invalid_credentials') || text.contains('invalid login')) return l.authInvalidCredentials;
  if (text.contains('user_already_exists') || text.contains('already registered')) return l.authUserExists;
  if (text.contains('weak_password')) return l.authWeakPassword;
  if (text.contains('rate_limit') || text.contains('over_request') || text.contains('over_email_send')) {
    return l.authTooManyRequests;
  }
  return failureMessage(context, error);
}
