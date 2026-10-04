import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/config/app_constants.dart';
import 'package:prostuti/core/config/remote_config.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/rate_limit/debouncer.dart';
import 'package:prostuti/core/services/media_service.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/utils/validators.dart';
import 'package:prostuti/core/widgets/app_image.dart';
import 'package:prostuti/core/widgets/skeleton.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:prostuti/features/home/application/home_helpers.dart';
import 'package:prostuti/features/onboarding/application/onboarding_flow.dart';
import 'package:prostuti/features/onboarding/data/districts.dart';
import 'package:prostuti/features/onboarding/presentation/widgets/onboarding_pickers.dart';
import 'package:prostuti/features/onboarding/presentation/widgets/onboarding_step_header.dart';
import 'package:prostuti/features/profile/data/profile.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';

/// Target exam types offered during onboarding (mirrors `exam_types.code`).
const onboardingExamTypes = ['bcs', 'bank', 'primary', 'ntrca', 'govt'];

String examTypeLabel(BuildContext context, String code) {
  final l = context.l10n;
  return switch (code) {
    'bcs' => l.onboardingExamBcs,
    'bank' => l.onboardingExamBank,
    'primary' => l.onboardingExamPrimary,
    'ntrca' => l.onboardingExamNtrca,
    _ => l.onboardingExamGovt,
  };
}

enum _UsernameStatus { idle, checking, available, taken, invalid, unknown }

/// Step 1: who you are and what you are preparing for.
class OnboardingProfileScreen extends ConsumerStatefulWidget {
  const OnboardingProfileScreen({super.key});

  @override
  ConsumerState<OnboardingProfileScreen> createState() => _OnboardingProfileScreenState();
}

class _OnboardingProfileScreenState extends ConsumerState<OnboardingProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _debouncer = Debouncer(const Duration(milliseconds: 500));

  String _originalUsername = '';
  _UsernameStatus _usernameStatus = _UsernameStatus.idle;
  District? _district;
  final _exams = <String>{'bcs'};
  int? _scheduleId;
  double _minutes = 120;
  bool _uploading = false;
  bool _saving = false;
  bool _scheduleTouched = false;

  @override
  void initState() {
    super.initState();
    final p = ref.read(currentProfileProvider).value;
    if (p != null) _prefill(p);
  }

  void _prefill(Profile p) {
    _name.text = p.fullName ?? '';
    _username.text = p.username;
    _originalUsername = p.username;
    _usernameStatus = p.username.isEmpty ? _UsernameStatus.idle : _UsernameStatus.available;
    _district = District.find(p.district);
    if (p.targetExams.isNotEmpty) {
      _exams
        ..clear()
        ..addAll(p.targetExams.where(onboardingExamTypes.contains));
      if (_exams.isEmpty) _exams.add('bcs');
    }
    _scheduleId = p.targetScheduleId;
    _minutes = p.dailyStudyMinutes.clamp(30, 480).toDouble();
  }

  @override
  void dispose() {
    _debouncer.dispose();
    _name.dispose();
    _username.dispose();
    super.dispose();
  }

  // --- Username availability -------------------------------------------------
  void _onUsernameChanged(String value) {
    final v = value.trim();
    if (Validators.username(v) != null) {
      _debouncer(() {});
      setState(() => _usernameStatus = v.isEmpty ? _UsernameStatus.idle : _UsernameStatus.invalid);
      return;
    }
    if (v.toLowerCase() == _originalUsername.toLowerCase()) {
      _debouncer(() {});
      setState(() => _usernameStatus = _UsernameStatus.available);
      return;
    }
    setState(() => _usernameStatus = _UsernameStatus.checking);
    _debouncer(() => unawaited(_checkUsername(v)));
  }

  Future<void> _checkUsername(String v) async {
    try {
      final ok = await ref.read(profileRepositoryProvider).isUsernameAvailable(v);
      if (!mounted || _username.text.trim() != v) return; // a newer keystroke won
      setState(() => _usernameStatus = ok ? _UsernameStatus.available : _UsernameStatus.taken);
    } on Object {
      if (mounted && _username.text.trim() == v) setState(() => _usernameStatus = _UsernameStatus.unknown);
    }
  }

  Widget? _usernameSuffix(ColorScheme scheme) => switch (_usernameStatus) {
    _UsernameStatus.checking => const Padding(
      padding: EdgeInsets.all(14),
      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
    ),
    _UsernameStatus.available => Icon(Icons.check_circle_rounded, color: scheme.primary),
    _UsernameStatus.taken || _UsernameStatus.invalid => Icon(Icons.error_rounded, color: scheme.error),
    _ => null,
  };

  String? _usernameHelper(BuildContext context) {
    final l = context.l10n;
    return switch (_usernameStatus) {
      _UsernameStatus.available => l.onboardingUsernameAvailable,
      _UsernameStatus.checking => l.onboardingUsernameChecking,
      _UsernameStatus.unknown => l.onboardingUsernameUnknown,
      _ => l.onboardingUsernameHint,
    };
  }

  // --- Avatar ------------------------------------------------------------------
  Future<void> _pickAvatar() async {
    final l = context.l10n;
    if (!ConnectivityService.instance.isOnline) {
      showInfoSnack(context, l.offlineUnavailable);
      return;
    }
    try {
      final bytes = await MediaService.instance.pickOne(maxDimension: AppConstants.avatarMaxDimension);
      if (bytes == null || !mounted) return;
      setState(() => _uploading = true);
      await ref.read(currentProfileProvider.notifier).uploadAvatar(bytes);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // --- Save --------------------------------------------------------------------
  Future<void> _save(int? effectiveScheduleId) async {
    final l = context.l10n;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_usernameStatus == _UsernameStatus.checking) {
      showInfoSnack(context, l.onboardingUsernameChecking);
      return;
    }
    if (_exams.isEmpty) {
      showInfoSnack(context, l.onboardingPickExam);
      return;
    }
    if (!ConnectivityService.instance.isOnline) {
      showInfoSnack(context, l.offlineUnavailable);
      return;
    }
    setState(() => _saving = true);
    try {
      await OnboardingFlow.advance(
        context,
        ref,
        OnboardingStep.interview,
        patch: {
          'full_name': _name.text.trim(),
          'username': _username.text.trim(),
          'district': _district?.nameBn,
          'target_exams': onboardingExamTypes.where(_exams.contains).toList(),
          'target_schedule_id': ?effectiveScheduleId,
          'daily_study_minutes': _minutes.round(),
        },
      );
    } on Object catch (e) {
      if (!mounted) return;
      if (AppFailure.from(e) is ConflictFailure) {
        setState(() => _usernameStatus = _UsernameStatus.taken);
        _formKey.currentState?.validate();
        showInfoSnack(context, l.onboardingUsernameTaken);
      } else {
        showErrorSnack(context, e);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Keeps the defaults (name from the e-mail, generated username, BCS) and
  /// moves on; everything can be edited later from the profile.
  Future<void> _skip() async {
    FocusScope.of(context).unfocus();
    if (!ConnectivityService.instance.isOnline) {
      showInfoSnack(context, context.l10n.offlineUnavailable);
      return;
    }
    setState(() => _saving = true);
    try {
      await OnboardingFlow.advance(context, ref, OnboardingStep.interview);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final avatarUrl = ref.watch(currentProfileProvider.select((p) => p.value?.avatarUrl));
    final schedules = ref.watch(examSchedulesProvider);
    final defaultId = ref.watch(remoteConfigProvider.select((c) => c.value?.defaultScheduleId));

    // Schedules matching the chosen exam types (all of them if none match).
    final all = schedules.value ?? const <ExamSchedule>[];
    final matching = all.where((s) => _exams.contains(s.examType)).toList();
    final visible = matching.isEmpty ? all : matching;
    final fallback = resolveTargetSchedule(
      visible,
      targetId: _scheduleTouched ? _scheduleId : (_scheduleId ?? defaultId),
      defaultId: defaultId,
      targetExams: onboardingExamTypes.where(_exams.contains).toList(),
    );
    final effectiveScheduleId = visible.any((s) => s.id == _scheduleId) ? _scheduleId : fallback?.id;

    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.xl),
            children: [
              const OnboardingStepHeader(step: 1),
              Gap.h24,
              Text(l.onboardingProfileTitle, style: theme.textTheme.headlineSmall),
              Gap.h4,
              Text(
                l.onboardingProfileSubtitle,
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              Gap.h24,
              Center(
                child: _AvatarPicker(url: avatarUrl, name: _name.text, uploading: _uploading, onTap: _pickAvatar),
              ),
              Gap.h24,
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                maxLength: 80,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l.onboardingFullName,
                  prefixIcon: const Icon(Icons.badge_outlined),
                  counterText: '',
                ),
                validator: (v) => (v == null || v.trim().length < 2) ? l.onboardingFullNameRequired : null,
              ),
              Gap.h16,
              TextFormField(
                controller: _username,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                onChanged: _onUsernameChanged,
                decoration: InputDecoration(
                  labelText: l.onboardingUsername,
                  prefixIcon: const Icon(Icons.alternate_email_rounded),
                  suffixIcon: _usernameSuffix(scheme),
                  helperText: _usernameHelper(context),
                ),
                validator: (v) {
                  if (Validators.username(v) != null) return l.validationUsername;
                  if (_usernameStatus == _UsernameStatus.taken) return l.onboardingUsernameTaken;
                  return null;
                },
              ),
              Gap.h16,
              _DistrictField(
                district: _district,
                onPick: () async {
                  final picked = await showDistrictPicker(context, selected: _district);
                  if (picked != null && mounted) setState(() => _district = picked);
                },
              ),
              _SectionTitle(icon: Icons.flag_rounded, title: l.onboardingTargetExams),
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                children: [
                  for (final code in onboardingExamTypes)
                    FilterChip(
                      label: Text(examTypeLabel(context, code)),
                      selected: _exams.contains(code),
                      onSelected: (on) => setState(() {
                        if (on) {
                          _exams.add(code);
                        } else if (_exams.length > 1) {
                          _exams.remove(code);
                        }
                      }),
                    ),
                ],
              ),
              _SectionTitle(icon: Icons.event_rounded, title: l.onboardingTargetSchedule),
              if (schedules.isLoading && !schedules.hasValue)
                const SkeletonShimmer(child: SkeletonBox(height: 72, radius: 16))
              else if (visible.isEmpty)
                Text(l.onboardingNoSchedules, style: theme.textTheme.bodyMedium)
              else
                for (final s in visible)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.sm),
                    child: ScheduleOption(
                      schedule: s,
                      selected: s.id == effectiveScheduleId,
                      onTap: () => setState(() {
                        _scheduleId = s.id;
                        _scheduleTouched = true;
                      }),
                    ),
                  ),
              Text(
                l.onboardingScheduleNote,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              _SectionTitle(icon: Icons.timer_outlined, title: l.onboardingDailyTime),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.sm),
                  child: Column(
                    children: [
                      Text(
                        l.onboardingDailyTimeValue(Fmt.minutes(_minutes.round(), bangla: context.isBn)),
                        style: theme.textTheme.titleMedium?.copyWith(color: scheme.primary),
                      ),
                      Slider(
                        value: _minutes,
                        min: 30,
                        max: 480,
                        divisions: 30,
                        label: Fmt.minutes(_minutes.round(), bangla: context.isBn),
                        onChanged: (v) => setState(() => _minutes = v),
                      ),
                      Text(
                        l.onboardingDailyTimeHint,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: _saving || _uploading ? null : () => _save(effectiveScheduleId),
                child: _saving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : Text(l.onboardingSaveContinue),
              ),
              TextButton(onPressed: _saving || _uploading ? null : _skip, child: Text(l.onboardingSkipStep)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Gap.xl, bottom: Gap.md),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          Gap.w8,
          Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
        ],
      ),
    );
  }
}

class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({required this.url, required this.name, required this.uploading, required this.onTap});

  final String? url;
  final String name;
  final bool uploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: context.l10n.onboardingAvatarPick,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: uploading ? null : onTap,
        child: Stack(
          children: [
            UserAvatar(name: name.isEmpty ? '?' : name, url: url, radius: 48),
            if (uploading)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), shape: BoxShape.circle),
                  child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                ),
              ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(Gap.sm),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
                child: Icon(Icons.photo_camera_rounded, size: 18, color: scheme.onPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DistrictField extends StatelessWidget {
  const _DistrictField({required this.district, required this.onPick});

  final District? district;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: Radii.button,
      onTap: onPick,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: l.onboardingDistrict,
          prefixIcon: const Icon(Icons.location_on_outlined),
          suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
        ),
        isEmpty: district == null,
        child: Text(district?.name(bangla: context.isBn) ?? '', style: theme.textTheme.bodyLarge),
      ),
    );
  }
}
