import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/validators.dart';
import 'package:prostuti/features/auth/data/auth_repository.dart';
import 'package:prostuti/features/auth/presentation/widgets/auth_scaffold.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(_email.text);
      if (mounted) setState(() => _sent = true);
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
      title: l.authForgotTitle,
      subtitle: l.authForgotBody,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_sent)
              Container(
                padding: const EdgeInsets.all(Gap.lg),
                decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: Radii.card),
                child: Row(
                  children: [
                    Icon(Icons.mark_email_read_outlined, color: scheme.onPrimaryContainer),
                    Gap.w12,
                    Expanded(
                      child: Text(l.authLinkSent, style: TextStyle(color: scheme.onPrimaryContainer)),
                    ),
                  ],
                ),
              )
            else ...[
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                validator: (v) => validationMessage(context, Validators.email(v)),
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(labelText: l.authEmail, prefixIcon: const Icon(Icons.mail_outline_rounded)),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.sm),
                  child: Text(_error!, style: TextStyle(color: scheme.error)),
                ),
              Gap.h24,
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                    : Text(l.authSendLink),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
