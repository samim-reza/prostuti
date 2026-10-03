import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/config/app_constants.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/l10n/l10n.dart';
import 'package:prostuti/core/offline/connectivity.dart';
import 'package:prostuti/core/services/media_service.dart';
import 'package:prostuti/core/theme/app_spacing.dart';
import 'package:prostuti/core/widgets/app_image.dart';
import 'package:prostuti/core/widgets/state_views.dart';
import 'package:prostuti/features/feed/application/feed_controller.dart';
import 'package:prostuti/features/feed/data/feed_repository.dart';
import 'package:prostuti/features/feed/data/post.dart';
import 'package:prostuti/features/feed/l10n/social_failures.dart';
import 'package:prostuti/features/feed/presentation/widgets/post_labels.dart';
import 'package:prostuti/features/profile/data/profile.dart';
import 'package:prostuti/features/profile/data/profile_repository.dart';

/// An image in the composer: either already on the post, or newly picked.
sealed class _ComposeImage {
  const _ComposeImage();
}

final class _ExistingImage extends _ComposeImage {
  const _ExistingImage(this.url);
  final String url;
}

final class _NewImage extends _ComposeImage {
  _NewImage(this.bytes);
  final Uint8List bytes;
}

/// Create (or, with [initialPost], edit) a post: up to 5000 characters and
/// four photos, with an audience selector.
///
/// Text-only posts work offline (queued with a client id); photo uploads
/// and edits need the network.
class ComposePostScreen extends ConsumerStatefulWidget {
  const ComposePostScreen({this.initialPost, super.key});

  /// Editing this post when set.
  final Post? initialPost;

  static const maxLength = 5000;

  /// Opens the editor for an existing post (no route needed).
  static Future<void> openEditor(BuildContext context, Post post) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => ComposePostScreen(initialPost: post)));

  @override
  ConsumerState<ComposePostScreen> createState() => _ComposePostScreenState();
}

class _ComposePostScreenState extends ConsumerState<ComposePostScreen> {
  late final TextEditingController _text = TextEditingController(text: widget.initialPost?.body ?? '');
  late final List<_ComposeImage> _images = [
    for (final url in widget.initialPost?.imageUrls ?? const <String>[]) _ExistingImage(url),
  ];
  late PostVisibility _visibility = widget.initialPost?.visibility ?? PostVisibility.public;

  bool _picking = false;
  bool _submitting = false;
  (int, int)? _upload;

  bool get _editing => widget.initialPost != null;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onText);
  }

  @override
  void dispose() {
    _text
      ..removeListener(_onText)
      ..dispose();
    super.dispose();
  }

  void _onText() => setState(() {});

  bool get _hasContent =>
      _text.text.trim().isNotEmpty ||
      _images.isNotEmpty ||
      (widget.initialPost?.kind ?? PostKind.text) != PostKind.text;

  bool get _canSubmit => !_submitting && _hasContent && _text.text.characters.length <= ComposePostScreen.maxLength;

  bool get _isDirty {
    final p = widget.initialPost;
    if (p == null) return _text.text.trim().isNotEmpty || _images.isNotEmpty;
    final kept = [
      for (final i in _images)
        if (i is _ExistingImage) i.url,
    ];
    return _text.text != (p.body ?? '') ||
        _visibility != p.visibility ||
        _images.any((i) => i is _NewImage) ||
        kept.length != p.imageUrls.length;
  }

  Future<void> _pickImages() async {
    final remaining = AppConstants.maxPostImages - _images.length;
    if (remaining <= 0) {
      showInfoSnack(context, context.l10n.feedPhotosLimit(context.n(AppConstants.maxPostImages)));
      return;
    }
    setState(() => _picking = true);
    try {
      final media = ref.read(mediaServiceProvider);
      // `pickMultiImage(limit:)` requires a limit of at least 2.
      final picked = remaining == 1 ? [?await media.pickOne()] : await media.pickMany(limit: remaining);
      if (!mounted) return;
      setState(() => _images.addAll(picked.take(remaining).map(_NewImage.new)));
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _chooseVisibility() async {
    final l = context.l10n;
    final picked = await showModalBottomSheet<PostVisibility>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.sm),
              child: Text(l.feedWhoCanSee, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            RadioGroup<PostVisibility>(
              groupValue: _visibility,
              onChanged: (v) => Navigator.pop(ctx, v),
              child: Column(
                children: [
                  for (final v in PostVisibility.values)
                    RadioListTile<PostVisibility>(
                      value: v,
                      secondary: Icon(v.icon),
                      title: Text(v.label(l)),
                      subtitle: Text(v.hint(l)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _visibility = picked);
  }

  Future<UserSummary> _author() async {
    final profile = ref.read(currentProfileProvider).value ?? await ref.read(currentProfileProvider.future);
    if (profile == null) throw const AuthFailure('not_authenticated');
    return UserSummary(
      id: profile.id,
      username: profile.username,
      fullName: profile.fullName,
      avatarUrl: profile.avatarUrl,
    );
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final l = context.l10n;
    final newImages = [
      for (final i in _images)
        if (i is _NewImage) i.bytes,
    ];
    // Photos (and edits) need the network; plain text can be queued offline.
    if ((_editing || newImages.isNotEmpty) && !ensureOnline(context)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _upload = null;
    });
    final repo = ref.read(feedRepositoryProvider);
    final actions = ref.read(postActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    void progress(int done, int total) {
      if (mounted) setState(() => _upload = (done, total));
    }

    try {
      final author = await _author();
      final original = widget.initialPost;
      if (original != null) {
        final updated = await repo.updatePost(
          original: original,
          body: _text.text,
          keptUrls: [
            for (final i in _images)
              if (i is _ExistingImage) i.url,
          ],
          newImages: newImages,
          visibility: _visibility,
          onProgress: progress,
        );
        actions.changed(updated);
        messenger.showSnackBar(SnackBar(content: Text(l.feedPostUpdated)));
      } else {
        final post = newImages.isEmpty
            ? await repo.createTextPost(author: author, body: _text.text, visibility: _visibility)
            : await repo.createPostWithImages(
                author: author,
                body: _text.text,
                images: newImages,
                visibility: _visibility,
                onProgress: progress,
              );
        actions.created(post);
        messenger.showSnackBar(SnackBar(content: Text(post.pendingSync ? l.offlineSaved : l.feedPostPublished)));
      }
      if (mounted) navigator.pop();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      if (AppFailure.from(e) is NetworkFailure && !ConnectivityService.instance.isOnline && newImages.isNotEmpty) {
        showInfoSnack(context, l.offlineUnavailable);
      } else {
        showSocialError(context, e);
      }
    }
  }

  Future<void> _onPopInvoked(bool didPop) async {
    if (didPop || _submitting) return;
    final l = context.l10n;
    final discard = await confirmDialog(
      context,
      title: l.feedDiscardTitle,
      message: l.feedDiscardBody,
      confirmLabel: l.feedDiscard,
      destructive: true,
    );
    if (discard && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final profile = ref.watch(currentProfileProvider).value;
    final upload = _upload;
    final status = !_submitting
        ? null
        : upload != null && upload.$1 < upload.$2
        ? l.feedUploadingImages(context.n(upload.$1), context.n(upload.$2))
        : (_editing ? l.feedSaving : l.feedPublishing);
    final length = _text.text.characters.length;
    final over = length > ComposePostScreen.maxLength;

    return PopScope(
      canPop: !_isDirty && !_submitting,
      onPopInvokedWithResult: (didPop, _) => unawaited(_onPopInvoked(didPop)),
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: _submitting ? null : () => Navigator.of(context).maybePop(),
          ),
          title: Text(_editing ? l.feedEditTitle : l.feedComposeTitle),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: Gap.md),
              child: FilledButton(
                onPressed: _canSubmit ? () => unawaited(_submit()) : null,
                style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
                child: Text(_editing ? l.feedSaveChanges : l.feedPublish),
              ),
            ),
          ],
          bottom: _submitting
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    value: upload != null && upload.$2 > 0 && upload.$1 < upload.$2 ? upload.$1 / upload.$2 : null,
                  ),
                )
              : null,
        ),
        body: AbsorbPointer(
          absorbing: _submitting,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.xl),
                  children: [
                    Row(
                      children: [
                        UserAvatar(name: profile?.displayName, url: profile?.avatarUrl, radius: 22),
                        Gap.w12,
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(profile?.displayName ?? '', style: theme.textTheme.titleSmall),
                              Gap.h4,
                              _AudienceChip(visibility: _visibility, onTap: () => unawaited(_chooseVisibility())),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Gap.h12,
                    TextField(
                      controller: _text,
                      autofocus: !_editing,
                      minLines: 6,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      style: theme.textTheme.bodyLarge,
                      decoration: InputDecoration(
                        hintText: l.feedComposeHint,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    if (_images.isNotEmpty) ...[
                      Gap.h12,
                      _ImagePreviews(images: _images, onRemove: (i) => setState(() => _images.removeAt(i))),
                    ],
                    if (status != null) ...[
                      Gap.h16,
                      Text(status, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              _ComposerToolbar(
                imageCount: _images.length,
                picking: _picking,
                onAddPhotos: () => unawaited(_pickImages()),
                counter: '${context.n(length)}/${context.n(ComposePostScreen.maxLength)}',
                counterOver: over,
                showCounter: length > 0,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AudienceChip extends StatelessWidget {
  const _AudienceChip({required this.visibility, required this.onTap});

  final PostVisibility visibility;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '${l.feedWhoCanSee} ${visibility.label(l)}',
      excludeSemantics: true,
      child: Material(
        color: scheme.secondaryContainer.withValues(alpha: 0.6),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.md),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(visibility.icon, size: 16, color: scheme.onSecondaryContainer),
                  Gap.w4,
                  Text(
                    visibility.label(l),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSecondaryContainer),
                  ),
                  Icon(Icons.arrow_drop_down_rounded, size: 20, color: scheme.onSecondaryContainer),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImagePreviews extends StatelessWidget {
  const _ImagePreviews({required this.images, required this.onRemove});

  final List<_ComposeImage> images;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: images.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: Gap.sm,
        crossAxisSpacing: Gap.sm,
      ),
      itemBuilder: (context, i) {
        final image = images[i];
        return ClipRRect(
          borderRadius: Radii.card,
          child: Stack(
            fit: StackFit.expand,
            children: [
              switch (image) {
                _ExistingImage(:final url) => AppNetworkImage(url: url),
                _NewImage(:final bytes) => Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  cacheWidth: (200 * dpr).round(),
                  gaplessPlayback: true,
                ),
              },
              Positioned(
                top: Gap.xs,
                right: Gap.xs,
                child: IconButton.filledTonal(
                  tooltip: l.feedRemovePhoto,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => onRemove(i),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ComposerToolbar extends StatelessWidget {
  const _ComposerToolbar({
    required this.imageCount,
    required this.picking,
    required this.onAddPhotos,
    required this.counter,
    required this.counterOver,
    required this.showCounter,
  });

  final int imageCount;
  final bool picking;
  final VoidCallback onAddPhotos;
  final String counter;
  final bool counterOver;
  final bool showCounter;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final full = imageCount >= AppConstants.maxPostImages;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.xs),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: full || picking ? null : onAddPhotos,
                icon: picking
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_photo_alternate_outlined),
                label: Text(l.feedAddPhotos),
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              ),
              Expanded(
                child: Text(
                  l.feedPhotosLimit(context.n(AppConstants.maxPostImages)),
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (showCounter)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                  child: Text(
                    counter,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: counterOver ? scheme.error : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
