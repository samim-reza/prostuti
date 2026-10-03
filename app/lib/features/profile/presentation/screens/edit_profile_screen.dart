import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:prostuti/core/config/app_constants.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/rate_limit/debouncer.dart';
import 'package:prostuti/core/services/media_service.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/utils/formatters.dart';
import 'package:prostuti/core/utils/validators.dart';
import 'package:prostuti/core/widgets/app_image.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/catalog/data/catalog.dart';
import 'package:prostuti/features/profile/application/profile_edit.dart';
import 'package:prostuti/features/profile/data/bd_districts.dart';
import 'package:prostuti/features/profile/data/profile.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';
import 'package:prostuti/features/profile/presentation/widgets/district_picker.dart';

class EditProfileScreen extends ConsumerWidget {
  const EditProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final async = ref.watch(currentProfileProvider);
    final profile = async.value;
    if (profile == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l.profileEditTitle)),
        body: async.hasError
            ? ErrorView(
                error: async.error!,
                onRetry: () => unawaited(ref.read(currentProfileProvider.notifier).reload()),
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }
    return _EditProfileForm(profile: profile);
  }
}

class _EditProfileForm extends ConsumerStatefulWidget {
  const _EditProfileForm({required this.profile});
  final Profile profile;

  @override
  ConsumerState<_EditProfileForm> createState() => _EditProfileFormState();
}

class _EditProfileFormState extends ConsumerState<_EditProfileForm> {
  static const _bioMax = 300;

  final _formKey = GlobalKey<FormState>();
  final _usernameDebounce = Debouncer(const Duration(milliseconds: 500));
  late final TextEditingController _fullName;
  late final TextEditingController _username;
  late final TextEditingController _bio;
  late final TextEditingController _occupation;
  late String? _district;
  late List<String> _targetExams;
  late int? _scheduleId;
  late int _minutes;
  late String _allowMessages;

  UsernameStatus _usernameStatus = UsernameStatus.unchanged;
  int _usernameCheckSeq = 0;
  bool _saving = false;
  bool _uploading = false;

  Profile get _original => widget.profile;

  @override
  void initState() {
    super.initState();
    final d = ProfileDraft.fromProfile(widget.profile);
    _fullName = TextEditingController(text: d.fullName)..addListener(_changed);
    _username = TextEditingController(text: d.username);
    _bio = TextEditingController(text: d.bio)..addListener(_changed);
    _occupation = TextEditingController(text: d.occupation)..addListener(_changed);
    _district = d.district;
    _targetExams = [...d.targetExams];
    _scheduleId = d.targetScheduleId;
    _minutes = d.dailyStudyMinutes.clamp(minStudyMinutes, maxStudyMinutes);
    _allowMessages = d.allowMessagesFrom;
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _usernameDebounce.dispose();
    _fullName.dispose();
    _username.dispose();
    _bio.dispose();
    _occupation.dispose();
    super.dispose();
  }

  ProfileDraft get _draft => ProfileDraft(
    fullName: _fullName.text,
    username: _username.text,
    bio: _bio.text,
    district: _district,
    occupation: _occupation.text,
    targetExams: _targetExams,
    targetScheduleId: _scheduleId,
    dailyStudyMinutes: _minutes,
    allowMessagesFrom: _allowMessages,
  );

  void _onUsernameChanged(String value) {
    final v = value.trim();
    final seq = ++_usernameCheckSeq;
    if (v == _original.username) {
      _usernameDebounce.call(() {});
      setState(() => _usernameStatus = UsernameStatus.unchanged);
      return;
    }
    if (Validators.username(v) != null) {
      setState(() => _usernameStatus = UsernameStatus.invalid);
      return;
    }
    setState(() => _usernameStatus = UsernameStatus.checking);
    _usernameDebounce.call(() => unawaited(_checkUsername(v, seq)));
  }

  Future<void> _checkUsername(String value, int seq) async {
    UsernameStatus status;
    if (!ConnectivityService.instance.isOnline) {
      status = UsernameStatus.unknown;
    } else {
      try {
        final free = await ref.read(profileRepositoryProvider).isUsernameAvailable(value);
        status = free ? UsernameStatus.available : UsernameStatus.taken;
      } on Object {
        status = UsernameStatus.unknown;
      }
    }
    // Ignore stale answers (the user kept typing).
    if (mounted && seq == _usernameCheckSeq) setState(() => _usernameStatus = status);
  }

  Future<void> _changeAvatar() async {
    final l = context.l10n;
    final hasAvatar = _original.avatarUrl?.isNotEmpty ?? false;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l.profileAvatarGallery),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l.profileAvatarCamera),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            if (hasAvatar)
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: Theme.of(ctx).colorScheme.error),
                title: Text(l.profileAvatarRemove),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (!ConnectivityService.instance.isOnline) {
      showInfoSnack(context, l.offlineUnavailable);
      return;
    }
    setState(() => _uploading = true);
    try {
      final notifier = ref.read(currentProfileProvider.notifier);
      if (choice == 'remove') {
        await notifier.save({'avatar_url': null});
      } else {
        final bytes = await ref
            .read(mediaServiceProvider)
            .pickOne(
              source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
              maxDimension: AppConstants.avatarMaxDimension,
            );
        if (bytes == null) return;
        await notifier.uploadAvatar(bytes);
      }
      if (mounted) showInfoSnack(context, l.profileAvatarUpdated);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickDistrict() async {
    final picked = await showDistrictPicker(context, selected: _district);
    if (picked != null && mounted) setState(() => _district = picked);
  }

  Future<void> _save() async {
    final l = context.l10n;
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    if (_usernameStatus == UsernameStatus.taken) {
      showInfoSnack(context, l.profileUsernameTaken);
      return;
    }
    final patch = buildProfilePatch(_original, _draft);
    if (patch.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    FocusScope.of(context).unfocus();
    final online = ConnectivityService.instance.isOnline;
    if (!online && patch.containsKey('username')) {
      showInfoSnack(context, l.profileUsernameNeedsInternet);
      return;
    }
    setState(() => _saving = true);
    try {
      final notifier = ref.read(currentProfileProvider.notifier);
      var synced = true;
      if (online) {
        await notifier.save(patch);
      } else {
        synced = await notifier.saveOfflineFirst(patch);
      }
      if (!mounted) return;
      showInfoSnack(context, synced ? l.profileSaved : l.offlineSaved);
      Navigator.of(context).pop();
    } on ConflictFailure {
      if (mounted) {
        setState(() => _usernameStatus = UsernameStatus.taken);
        showInfoSnack(context, l.profileUsernameTaken);
      }
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDiscard() async {
    final l = context.l10n;
    final discard = await confirmDialog(
      context,
      title: l.profileDiscardTitle,
      message: l.profileDiscardBody,
      confirmLabel: l.profileDiscard,
      destructive: true,
    );
    if (discard && mounted) Navigator.of(context).pop();
  }

  Widget? _usernameSuffix(ColorScheme scheme) => switch (_usernameStatus) {
    UsernameStatus.checking => const Padding(
      padding: EdgeInsets.all(14),
      child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
    ),
    UsernameStatus.available => Icon(Icons.check_circle_rounded, color: scheme.primary),
    UsernameStatus.taken => Icon(Icons.error_rounded, color: scheme.error),
    _ => null,
  };

  String? _usernameHelper(AppLocalizations l) => switch (_usernameStatus) {
    UsernameStatus.available => l.profileUsernameAvailable,
    UsernameStatus.checking => l.profileUsernameChecking,
    UsernameStatus.unknown => l.profileUsernameUnknown,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bangla = context.isBn;
    final dirty = buildProfilePatch(_original, _draft).isNotEmpty;
    final profile = ref.watch(currentProfileProvider.select((p) => p.value)) ?? _original;
    final examTypes = ref.watch(examTypesProvider).value;
    final schedules = ref.watch(examSchedulesProvider).value ?? const <ExamSchedule>[];

    return PopScope(
      canPop: !dirty || _saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmDiscard());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.profileEditTitle),
          actions: [
            TextButton(onPressed: _saving ? null : () => unawaited(_save()), child: Text(l.save)),
            Gap.w8,
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl),
            children: [
              Center(
                child: Semantics(
                  button: true,
                  label: l.profileAvatarChange,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _uploading ? null : () => unawaited(_changeAvatar()),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        UserAvatar(name: profile.displayName, url: profile.avatarUrl, radius: 48),
                        if (_uploading)
                          const SizedBox.square(dimension: 96, child: CircularProgressIndicator(strokeWidth: 3)),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: CircleAvatar(
                            radius: 17,
                            backgroundColor: scheme.primary,
                            child: Icon(Icons.photo_camera_rounded, size: 18, color: scheme.onPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Gap.h24,
              _SectionLabel(l.profileSectionBasic),
              TextFormField(
                controller: _fullName,
                maxLength: 80,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l.profileFullName,
                  prefixIcon: const Icon(Icons.badge_outlined),
                  counterText: '',
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? l.validationRequired : null,
              ),
              Gap.h16,
              TextFormField(
                controller: _username,
                maxLength: 24,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                onChanged: _onUsernameChanged,
                decoration: InputDecoration(
                  labelText: l.profileUsername,
                  prefixText: '@',
                  prefixIcon: const Icon(Icons.alternate_email_rounded),
                  suffixIcon: _usernameSuffix(scheme),
                  helperText: _usernameHelper(l),
                  errorText: _usernameStatus == UsernameStatus.taken ? l.profileUsernameTaken : null,
                  counterText: '',
                ),
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.isEmpty && _original.username.isEmpty) return null;
                  return Validators.username(value) == null ? null : l.validationUsername;
                },
              ),
              Gap.h16,
              TextFormField(
                controller: _bio,
                maxLength: _bioMax,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: l.profileBio,
                  hintText: l.profileBioHint,
                  alignLabelWithHint: true,
                ),
                buildCounter: (context, {required currentLength, required isFocused, required maxLength}) => Text(
                  '${context.n(currentLength)}/${context.n(maxLength ?? _bioMax)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: currentLength > _bioMax - 20 ? scheme.error : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Gap.h8,
              _PickerField(
                icon: Icons.place_outlined,
                label: l.profileDistrict,
                value: districtLabel(_district, bangla: bangla),
                placeholder: l.profileDistrictPick,
                onTap: () => unawaited(_pickDistrict()),
              ),
              Gap.h16,
              TextFormField(
                controller: _occupation,
                maxLength: 60,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: l.profileOccupation,
                  hintText: l.profileOccupationHint,
                  prefixIcon: const Icon(Icons.work_outline_rounded),
                  counterText: '',
                ),
              ),
              Gap.h24,
              _SectionLabel(l.profileSectionPreparation),
              Text(l.profileTargetExams, style: theme.textTheme.titleSmall),
              Gap.h8,
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                children: [
                  for (final t
                      in examTypes ?? [for (final c in _targetExams) ExamTypeInfo(code: c, nameBn: c, nameEn: c)])
                    FilterChip(
                      label: Text(t.name(bangla: bangla)),
                      selected: _targetExams.contains(t.code),
                      onSelected: (on) => setState(() {
                        if (on) {
                          _targetExams = [..._targetExams, t.code];
                        } else if (_targetExams.length > 1) {
                          _targetExams = _targetExams.where((c) => c != t.code).toList();
                        }
                      }),
                    ),
                ],
              ),
              Gap.h16,
              DropdownButtonFormField<int?>(
                // Rebuild once schedules arrive so the saved choice shows up.
                key: ValueKey(schedules.length),
                initialValue: schedules.any((s) => s.id == _scheduleId) ? _scheduleId : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l.profileTargetSchedule,
                  prefixIcon: const Icon(Icons.event_outlined),
                ),
                items: [
                  DropdownMenuItem<int?>(child: Text(l.profileNoSchedule)),
                  for (final s in schedules)
                    DropdownMenuItem<int?>(
                      value: s.id,
                      child: Text(
                        '${s.title(context)} · ${Fmt.date(s.expectedDate, bangla: bangla)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _scheduleId = v),
              ),
              Gap.h16,
              Row(
                children: [
                  Expanded(child: Text(l.profileDailyStudy, style: theme.textTheme.titleSmall)),
                  Text(
                    Fmt.minutes(_minutes, bangla: bangla),
                    style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary),
                  ),
                ],
              ),
              Slider(
                value: _minutes.clamp(minStudyMinutes, 720).toDouble(),
                min: minStudyMinutes.toDouble(),
                max: 720,
                divisions: (720 - minStudyMinutes) ~/ 15,
                label: Fmt.minutes(_minutes, bangla: bangla),
                onChanged: (v) => setState(() => _minutes = v.round()),
              ),
              Gap.h16,
              _SectionLabel(l.profileSectionPrivacy),
              Text(l.profileAllowMessages, style: theme.textTheme.titleSmall),
              Gap.h8,
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'friends',
                    icon: const Icon(Icons.group_rounded),
                    label: Text(l.profileAllowFriends),
                  ),
                  ButtonSegment(
                    value: 'everyone',
                    icon: const Icon(Icons.public_rounded),
                    label: Text(l.profileAllowEveryone),
                  ),
                ],
                selected: {_allowMessages},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _allowMessages = s.first),
              ),
              Gap.h32,
              FilledButton(
                onPressed: _saving ? null : () => unawaited(_save()),
                child: _saving
                    ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                    : Text(l.profileSaveChanges),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.icon,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String? value;
  final String placeholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: Radii.button,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: const Icon(Icons.expand_more_rounded),
        ),
        child: value == null
            ? Text(placeholder, style: theme.textTheme.bodyLarge?.copyWith(color: theme.hintColor))
            : Text(value!, style: theme.textTheme.bodyLarge),
      ),
    );
  }
}
