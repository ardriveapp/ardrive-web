import 'dart:ui' as ui;

import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// How long a tile takes to fade from its placeholder to the photo.
const Duration galleryTileFadeDuration = Duration(milliseconds: 180);

/// One photo in a gallery.
///
/// It never fetches: the caller passes an [image] it already has a provider
/// for, or null while it is not loaded, and the tile shows what it can.
///
/// - Skeleton: [image] and [lowResImage] are null. A plain block, in
///   [placeholderColor] (the photo's dominant colour) when given.
/// - Blur-up: [lowResImage] is shown blurred until [image] has its first
///   frame, then [image] fades in over [galleryTileFadeDuration] (instantly
///   when the platform asks for reduced motion) and the blurred layer is
///   removed.
/// - Failed: [failed] is true, or [image] could not be decoded. A quiet icon
///   and [failedLabel] for a screen reader.
/// - Pending: [pending], an upload that is not permanent yet.
/// - Selected: [selected]. The photo insets and a check mark shows.
/// - Focus: the keyboard focus ring, drawn inside the tile so neighbours and
///   the gallery's edge never cover or clip it.
///
/// [content] replaces the photo, for a tile that is not one (a folder, a
/// document): it keeps the selection, focus, menu and click behaviour.
///
/// Clicks follow the list's rows: a mouse click calls [onTap] at once (it
/// selects), the second click of a double-click, a touch or stylus tap, and
/// Enter or Space call [onOpen]. Nothing waits for a double-click window.
class ArDriveGalleryTile extends StatefulWidget {
  const ArDriveGalleryTile({
    super.key,
    required this.name,
    this.image,
    this.lowResImage,
    this.placeholderColor,
    this.failed = false,
    this.pending = false,
    this.selected = false,
    this.onTap,
    this.onOpen,
    this.onSecondaryTap,
    this.onLongPress,
    this.focusNode,
    this.content,
    this.typeLabel,
    this.trailing,
    this.keepTrailing = false,
    this.failedLabel = 'Could not load',
    this.pendingLabel = 'Upload pending',
  });

  /// The file's name: what a screen reader announces.
  final String name;

  final ImageProvider? image;

  /// A small image shown blurred while [image] loads.
  final ImageProvider? lowResImage;

  /// The skeleton's colour, e.g. the photo's dominant colour from its small
  /// thumbnail. Defaults to a container token.
  final Color? placeholderColor;

  final bool failed;
  final bool pending;
  final bool selected;

  /// A mouse click: select. Called immediately.
  final VoidCallback? onTap;

  /// Open: a double-click, a touch tap, Enter, Space, or a screen reader's
  /// activate. Without it those select, through [onTap].
  final VoidCallback? onOpen;

  final VoidCallback? onSecondaryTap;

  /// A long press (a finger held on the tile): start selecting.
  final VoidCallback? onLongPress;
  final FocusNode? focusNode;

  /// Drawn in place of the photo, with the tile's rounded clip.
  final Widget? content;

  /// What kind of thing the tile is ("JPEG image", "Folder"): read after the
  /// name by a screen reader.
  final String? typeLabel;

  /// A control over the tile's top right, such as its menu button. Shown
  /// while the pointer is on the tile, the tile has focus or is selected, or
  /// [keepTrailing] is set.
  final Widget? trailing;
  final bool keepTrailing;

  final String failedLabel;
  final String pendingLabel;

  /// How far a selected photo insets.
  static const double selectedInset = ArDriveSpacing.xs;

  @override
  State<ArDriveGalleryTile> createState() => _ArDriveGalleryTileState();
}

class _ArDriveGalleryTileState extends State<ArDriveGalleryTile> {
  final _doubleClick = ArDriveDoubleClick<bool>();
  PointerDeviceKind? _tapKind;
  bool _hovered = false;
  bool _focusWithin = false;

  /// [ArDriveGalleryTile.image] could not be decoded.
  bool _decodeFailed = false;

  /// The photo has shown and its fade is over, so the blurred layer is gone.
  bool _settled = false;

  @override
  void didUpdateWidget(ArDriveGalleryTile old) {
    super.didUpdateWidget(old);
    if (old.image != widget.image) {
      _decodeFailed = false;
      _settled = false;
    }
  }

  @override
  void dispose() {
    _doubleClick.dispose();
    super.dispose();
  }

  void _onTap() {
    final kind = _tapKind;
    _tapKind = null;
    final onOpen = widget.onOpen;
    if (onOpen != null && ArDriveDoubleClick.tapOpens(kind)) {
      _doubleClick.reset();
      onOpen();
      return;
    }
    if (onOpen != null && _doubleClick.completes(true)) {
      onOpen();
      return;
    }
    widget.onTap?.call();
    if (onOpen != null) _doubleClick.arm(true);
  }

  void _markFailed() {
    if (_decodeFailed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_decodeFailed) setState(() => _decodeFailed = true);
    });
  }

  void _markSettled() {
    if (_settled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_settled) setState(() => _settled = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ArDriveTheme.of(context).themeData.colorTokens;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final fade = reduceMotion ? Duration.zero : galleryTileFadeDuration;
    final inset = widget.selected ? ArDriveGalleryTile.selectedInset : 0.0;
    final failed = widget.failed || _decodeFailed;
    final activates = widget.onOpen ?? widget.onTap;

    final labels = [
      widget.name,
      if (widget.typeLabel != null) widget.typeLabel!,
      if (failed) widget.failedLabel,
      if (widget.pending) widget.pendingLabel,
    ].join(', ');

    Widget failedView() => ColoredBox(
          key: const ValueKey('gallery-tile-failed'),
          color: tokens.containerL2,
          child: Center(
            child: ArDriveIcons.image(size: 24, color: tokens.iconMid),
          ),
        );

    Widget photo() {
      if (widget.content != null) return widget.content!;
      if (failed) return failedView();
      final lowRes = widget.lowResImage;
      final full = widget.image;
      return Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            key: const ValueKey('gallery-tile-skeleton'),
            color: widget.placeholderColor ?? tokens.containerL2,
          ),
          if (lowRes != null && !_settled)
            ImageFiltered(
              key: const ValueKey('gallery-tile-blur'),
              imageFilter: ui.ImageFilter.blur(
                sigmaX: 8,
                sigmaY: 8,
                tileMode: TileMode.clamp,
              ),
              child: Image(
                image: lowRes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          if (full != null)
            Image(
              key: const ValueKey('gallery-tile-image'),
              image: full,
              fit: BoxFit.cover,
              frameBuilder: (context, child, frame, sync) {
                final shown = sync || frame != null;
                if (sync) _markSettled();
                return AnimatedOpacity(
                  opacity: shown ? 1 : 0,
                  duration: sync ? Duration.zero : fade,
                  onEnd: shown ? _markSettled : null,
                  child: child,
                );
              },
              errorBuilder: (_, __, ___) {
                _markFailed();
                return failedView();
              },
            ),
        ],
      );
    }

    return Semantics(
      label: labels,
      image: true,
      button: activates != null,
      selected: widget.selected,
      excludeSemantics: true,
      onTap: activates,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (value) => setState(() => _focusWithin = value),
        child: ArDriveFocusable(
          onActivate: activates == null
              ? null
              : () => (widget.onOpen ?? widget.onTap)!(),
          focusNode: widget.focusNode,
          radius: ArDriveRadius.sm,
          // Inside the tile: a 2 px stroke centred 1 px in.
          inflate: -1,
          child: MouseRegion(
            cursor: activates != null
                ? SystemMouseCursors.click
                : MouseCursor.defer,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _tapKind = d.kind,
              onTapCancel: () => _tapKind = null,
              onTap: _onTap,
              onSecondaryTap: widget.onSecondaryTap,
              onLongPress: widget.onLongPress,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedPadding(
                    duration: fade,
                    padding: EdgeInsets.all(inset),
                    child: ClipRRect(
                      key: const ValueKey('gallery-tile-photo'),
                      borderRadius: BorderRadius.circular(ArDriveRadius.sm),
                      child: photo(),
                    ),
                  ),
                  if (widget.pending)
                    Positioned(
                      left: inset + ArDriveSpacing.xxs,
                      bottom: inset + ArDriveSpacing.xxs,
                      child: DecoratedBox(
                        key: const ValueKey('gallery-tile-pending'),
                        // A light disc in light, a dark one in dark: legible
                        // over any photo, unlike a scrim under a theme icon.
                        decoration: BoxDecoration(
                          color: tokens.containerL1,
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(ArDriveSpacing.xxs),
                          child: ArDriveIcons.cloudSync(
                            size: 14,
                            color: tokens.iconHigh,
                          ),
                        ),
                      ),
                    ),
                  if (widget.trailing != null &&
                      (_hovered ||
                          _focusWithin ||
                          widget.selected ||
                          widget.keepTrailing))
                    Positioned(
                      right: inset + ArDriveSpacing.xxs,
                      top: inset + ArDriveSpacing.xxs,
                      child: DecoratedBox(
                        key: const ValueKey('gallery-tile-trailing'),
                        decoration: BoxDecoration(
                          color: tokens.containerL1,
                          shape: BoxShape.circle,
                        ),
                        child: widget.trailing!,
                      ),
                    ),
                  if (widget.selected)
                    Positioned(
                      left: ArDriveSpacing.xxs,
                      top: ArDriveSpacing.xxs,
                      child: DecoratedBox(
                        key: const ValueKey('gallery-tile-selected'),
                        decoration: BoxDecoration(
                          color: tokens.buttonPrimaryDefault,
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(ArDriveSpacing.xxs),
                          child: ArDriveIcons.checkmark(
                            size: 14,
                            color: tokens.textOnPrimary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
