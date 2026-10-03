import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/router/routes.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/validators.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/auth/data/auth_repository.dart';
import 'package:prostuti/features/auth/presentation/widgets/auth_scaffold.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _agreed = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _username, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final l = context.l10n;
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    if (!_agreed) {
      setState(() => _error = l.authAgreeRequired);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final signedIn = await ref
          .read(authRepositoryProvider)
          .signUp(
            email: _email.text,
            password: _password.text,
            fullName: _name.text,
            username: _username.text,
            locale: context.isBn ? 'bn' : 'en',
          );
      if (!mounted) return;
      if (!signedIn) {
        showInfoSnack(context, l.authCheckEmail);
        context.go(Routes.login);
      }
      // Otherwise the router redirects to onboarding automatically.
    } on Object catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return AuthScaffold(
      title: l.authRegisterTitle,
      subtitle: l.authRegisterSubtitle,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              maxLength: 80,
              validator: (v) => validationMessage(context, Validators.required(v)),
              decoration: InputDecoration(
                labelText: l.authFullName,
                prefixIcon: const Icon(Icons.badge_outlined),
                counterText: '',
              ),
            ),
            Gap.h16,
            TextFormField(
              controller: _username,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newUsername],
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? null : validationMessage(context, Validators.username(v)),
              decoration: InputDecoration(
                labelText: l.authUsername,
                hintText: l.authUsernameHint,
                prefixIcon: const Icon(Icons.alternate_email_rounded),
              ),
            ),
            Gap.h16,
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              validator: (v) => validationMessage(context, Validators.email(v)),
              decoration: InputDecoration(labelText: l.authEmail, prefixIcon: const Icon(Icons.mail_outline_rounded)),
            ),
            Gap.h16,
            PasswordField(
              controller: _password,
              label: l.authPassword,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              validator: (v) => validationMessage(context, Validators.password(v)),
            ),
            Gap.h16,
            PasswordField(
              controller: _confirm,
              label: l.authConfirmPassword,
              autofillHints: const [AutofillHints.newPassword],
              validator: (v) => v != _password.text ? l.authPasswordsDontMatch : null,
              onSubmitted: (_) => _submit(),
            ),
            Gap.h8,
            CheckboxListTile(
              value: _agreed,
              onChanged: (v) => setState(() => _agreed = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l.authAgreeTerms, style: Theme.of(context).textTheme.bodyMedium),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.sm),
                child: Text(_error!, style: TextStyle(color: scheme.error)),
              ),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                  : Text(l.authCreateAccount),
            ),
            Gap.h16,
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(child: Text(l.authHaveAccount)),
                TextButton(onPressed: () => context.pushReplacement(Routes.login), child: Text(l.authLogin)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
