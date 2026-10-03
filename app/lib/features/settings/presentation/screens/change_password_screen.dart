import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/theme/app_colors.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/validators.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/settings/application/password_strength.dart';
import 'package:prostuti/features/settings/data/settings_repository.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _password.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _password
      ..removeListener(_onChanged)
      ..dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _validatePassword(String? v) {
    final l = context.l10n;
    return switch (Validators.password(v)) {
      'required' => l.validationRequired,
      'password_too_short' => l.validationPassword,
      _ => null,
    };
  }

  String? _validateConfirm(String? v) {
    final l = context.l10n;
    if (v == null || v.isEmpty) return l.validationRequired;
    if (v != _password.text) return l.settingsPasswordMismatch;
    return null;
  }

  String _errorText(Object error) {
    final l = context.l10n;
    final f = AppFailure.from(error);
    if (f is AuthFailure) {
      switch (f.code) {
        case 'same_password':
          return l.settingsPasswordSame;
        case 'weak_password':
          return l.settingsPasswordWeak;
        case 'reauthentication_needed':
        case 'session_not_found':
          return l.settingsPasswordReauth;
      }
    }
    return failureMessage(context, error);
  }

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    if (!ConnectivityService.instance.isOnline) {
      showInfoSnack(context, context.l10n.offlineUnavailable);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(settingsRepositoryProvider).updatePassword(_password.text);
      if (!mounted) return;
      showInfoSnack(context, context.l10n.settingsPasswordChanged);
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) showInfoSnack(context, _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final toggle = IconButton(
      tooltip: _obscure ? l.settingsShowPassword : l.settingsHidePassword,
      onPressed: () => setState(() => _obscure = !_obscure),
      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
    );

    return Scaffold(
      appBar: AppBar(title: Text(l.settingsChangePassword)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(Gap.lg),
          children: [
            Text(
              l.settingsChangePasswordIntro,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            Gap.h24,
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: l.settingsNewPassword,
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: toggle,
              ),
              validator: _validatePassword,
            ),
            Gap.h8,
            PasswordStrengthBar(strength: passwordStrength(_password.text)),
            Gap.h16,
            TextFormField(
              controller: _confirm,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              enabled: !_busy,
              onFieldSubmitted: (_) => unawaited(_submit()),
              decoration: InputDecoration(
                labelText: l.settingsConfirmPassword,
                prefixIcon: const Icon(Icons.lock_reset_rounded),
              ),
              validator: _validateConfirm,
            ),
            Gap.h24,
            FilledButton(
              onPressed: _busy ? null : () => unawaited(_submit()),
              child: _busy
                  ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                  : Text(l.settingsUpdatePassword),
            ),
          ],
        ),
      ),
    );
  }
}

/// Four-segment strength meter with a label.
class PasswordStrengthBar extends StatelessWidget {
  const PasswordStrengthBar({required this.strength, super.key});

  /// 0…4 from [passwordStrength].
  final int strength;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (strength) {
      0 => ('', scheme.outlineVariant),
      1 => (l.settingsStrengthWeak, AppColors.danger),
      2 => (l.settingsStrengthFair, AppColors.warning),
      3 => (l.settingsStrengthGood, AppColors.info),
      _ => (l.settingsStrengthStrong, AppColors.success),
    };
    return Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) Gap.w4,
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 4,
              decoration: BoxDecoration(
                color: i < strength ? color : scheme.outlineVariant.withValues(alpha: 0.5),
                borderRadius: Radii.chip,
              ),
            ),
          ),
        ],
        Gap.w12,
        SizedBox(
          width: 72,
          child: Text(
            label,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
