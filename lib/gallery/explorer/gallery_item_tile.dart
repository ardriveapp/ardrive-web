import 'package:ardrive/gallery/explorer/gallery_selection.dart';
import 'package:ardrive/gallery/image_loader/gallery_image_loader.dart';
import 'package:ardrive/gallery/image_loader/gallery_variant_picker.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/pages/drive_detail/models/drive_table_columns.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The aspect ratio the gallery lays a folder tile out with: a small, wide
/// tile, so the photos below still lead.
const double galleryFolderAspectRatio = 3.4;

/// The folder tile's aspect ratio on a phone, where two folders share a row
/// and the row is stretched to the screen's width: wider, so the tile lands
/// near 48 px tall on common phones, like a folder chip in other drives.
const double galleryFolderAspectRatioPhone = 3.8;

/// The height of a folder tile's row.
const double galleryFolderRowHeight = 56;

/// The aspect ratio of a quiet type tile (a document, an archive, a video
/// with no poster): a portrait page, narrower than a photo, so a mixed folder
/// is not a wall of squares.
const double galleryTypeTileAspectRatio = 3 / 4;

/// What the gallery shows an item as.
enum GalleryTileKind { folder, image, other }

/// Folders are folders; images, and videos that have a thumbnail to show as a
/// poster, are photos; every other file is a quiet type tile.
GalleryTileKind galleryTileKindOf(ArDriveDataTableItem item) {
  if (item is FolderDataTableItem) return GalleryTileKind.folder;
  if (item is FileDataTableItem) {
    if (FileTypeHelper.isImage(item.contentType)) return GalleryTileKind.image;
    if (FileTypeHelper.isVideo(item.contentType) &&
        (item.thumbnail?.variants.isNotEmpty ?? false)) {
      return GalleryTileKind.image;
    }
  }
  return GalleryTileKind.other;
}

/// The thumbnail's renditions as the loader reads them.
List<GalleryVariant> galleryVariantsOf(FileDataTableItem file) => [
      for (final v in file.thumbnail?.variants ?? const [])
        GalleryVariant(
          txId: v.txId,
          size: v.size,
          width: v.width,
          height: v.height,
        ),
    ];

/// width / height of a photo from its largest thumbnail variant, or null when
/// there is none to size it from (the layout then uses a square).
double? galleryAspectRatioOf(ArDriveDataTableItem item) {
  if (item is! FileDataTableItem) return null;
  if (galleryTileKindOf(item) == GalleryTileKind.other) {
    return galleryTypeTileAspectRatio;
  }
  GalleryVariant? best;
  for (final v in galleryVariantsOf(item)) {
    if (v.width <= 0 || v.height <= 0) continue;
    if (best == null || v.width * v.height > best.width * best.height) {
      best = v;
    }
  }
  return best == null ? null : best.width / best.height;
}

/// One tile of the explorer gallery: a photo, a quiet type tile or a folder.
///
/// It is the [ArDriveGalleryTile] with the explorer's behaviour on it: the
/// row model's clicks (reported to [onClick] with their modifier), the same
/// menu as the list's row on a menu button and on a right-click, and the
/// image loader for photos.
class GalleryItemTile extends StatefulWidget {
  const GalleryItemTile({
    super.key,
    required this.item,
    required this.drive,
    required this.size,
    required this.selected,
    required this.focusNode,
    required this.loader,
    required this.onClick,
    required this.onOpen,
    required this.onSelectForMenu,
    required this.onLongPress,
  });

  final ArDriveDataTableItem item;
  final Drive drive;
  final Size size;
  final bool selected;
  final FocusNode focusNode;
  final GalleryImageLoader loader;

  /// A mouse click, with the modifier it carried.
  final void Function(GalleryClickKind kind) onClick;

  /// A double-click, a touch tap or Enter.
  final VoidCallback onOpen;

  /// A right-click: choose the item first when it is not chosen.
  final VoidCallback onSelectForMenu;
  final VoidCallback onLongPress;

  @override
  State<GalleryItemTile> createState() => _GalleryItemTileState();
}

class _GalleryItemTileState extends State<GalleryItemTile> {
  final _menu = ArDriveDropdownController();
  bool _keepMenu = false;

  GalleryImageHandle? _handle;
  String? _handleKey;
  bool _onScreen = false;
  bool _reportScheduled = false;
  ScrollPosition? _position;
  double _dpr = 1;

  bool get _isImage => galleryTileKindOf(widget.item) == GalleryTileKind.image;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _position) {
      _position?.removeListener(_report);
      _position = position;
      _position?.addListener(_report);
    }
    _dpr = MediaQuery.devicePixelRatioOf(context);
    _acquire();
  }

  @override
  void didUpdateWidget(GalleryItemTile old) {
    super.didUpdateWidget(old);
    _acquire();
    // The list rebuilds its tiles when its size changes, which moves no
    // scroll position: a taller window brings tiles into view all the same.
    if (!_reportScheduled) {
      _reportScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _reportScheduled = false;
        _report();
      });
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_report);
    _handle?.release();
    super.dispose();
  }

  /// Asks the loader for this tile's image, again if the file, the size or
  /// the screen's density changed.
  void _acquire() {
    final item = widget.item;
    if (!_isImage || item is! FileDataTableItem) {
      _release();
      return;
    }
    final key = [
      item.id,
      item.dataTxId,
      galleryVariantsOf(item).map((v) => v.txId).join(','),
      widget.size,
      _dpr,
    ].join('|');
    if (key == _handleKey) return;
    _release();
    _handleKey = key;
    final isPrivate = widget.drive.isPrivate;
    final handle = widget.loader.acquire(
      GalleryImageRequest(
        fileId: item.fileId,
        isPrivate: isPrivate,
        variants: galleryVariantsOf(item),
        // The original is only ever a stand-in for a missing (or, on a public
        // file, too small) thumbnail; its dimensions are not known here.
        original: (item.size ?? 0) <= 0
            ? null
            : GalleryVariant(
                txId: item.dataTxId,
                size: item.size ?? 0,
                width: 0,
                height: 0,
              ),
        tileWidth: widget.size.width,
        tileHeight: widget.size.height,
        devicePixelRatio: _dpr,
      ),
    );
    _handle = handle;
    _onScreen = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
  }

  void _release() {
    _handle?.release();
    _handle = null;
    _handleKey = null;
  }

  /// Tells the loader whether the tile is on screen, and how near the middle
  /// of it, so only what is seen is fetched, nearest first.
  void _report() {
    final handle = _handle;
    if (!mounted || handle == null) return;
    final box = context.findRenderObject();
    final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        viewport is! RenderBox ||
        !viewport.hasSize) {
      return;
    }
    final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    final bottom = top + box.size.height;
    final height = viewport.size.height;
    final onScreen = bottom > 0 && top < height;
    final wasOnScreen = _onScreen;
    _onScreen = onScreen;
    // A tile that failed is tried again the next time it scrolls into view.
    final value = handle.value;
    if (onScreen &&
        !wasOnScreen &&
        value.status == GalleryImageStatus.failed &&
        value.failure == GalleryFailureReason.fetchFailed) {
      handle.retry();
    }
    handle.updatePosition(
      onScreen: onScreen,
      priority: ((top + bottom) / 2 - height / 2).abs(),
    );
  }

  GalleryClickKind _kindOfClick() {
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed || keyboard.isMetaPressed) {
      return GalleryClickKind.toggle;
    }
    if (keyboard.isShiftPressed) return GalleryClickKind.range;
    return GalleryClickKind.plain;
  }

  void _rightClick() {
    widget.onSelectForMenu();
    // The menu button is only drawn once the tile is chosen: keep it, then
    // open the menu on the next frame.
    setState(() => _keepMenu = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _menu.open();
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final l10n = appLocalizationsOf(context);
    final type = driveTableTypeLabel(
      l10n,
      driveTableType(contentType: item.contentType, name: item.name),
    );

    final trailing = _TileMenu(
      item: item,
      drive: widget.drive,
      controller: _menu,
      onOpenChanged: (open) {
        if (!open && _keepMenu && mounted) setState(() => _keepMenu = false);
      },
    );

    Widget tile({
      ImageProvider? image,
      bool failed = false,
      Widget? content,
    }) =>
        ArDriveGalleryTile(
          name: item.name,
          typeLabel: type,
          image: image,
          failed: failed,
          content: content,
          pending: item is FileDataTableItem &&
              item.fileStatusFromTransactions == TransactionStatus.pending,
          selected: widget.selected,
          focusNode: widget.focusNode,
          failedLabel: l10n.galleryCouldNotLoad,
          pendingLabel: l10n.galleryUploadPending,
          onTap: () => widget.onClick(_kindOfClick()),
          onOpen: widget.onOpen,
          onSecondaryTap: _rightClick,
          onLongPress: widget.onLongPress,
          trailing: trailing,
          keepTrailing: _keepMenu,
        );

    final handle = _handle;
    if (handle != null) {
      return ValueListenableBuilder<GalleryImageState>(
        valueListenable: handle,
        builder: (context, state, _) => dimIfHidden(
          item.isHidden,
          tile(
            image: state.image,
            failed: state.status == GalleryImageStatus.failed,
          ),
        ),
      );
    }

    return dimIfHidden(
      item.isHidden,
      tile(
        content: item is FolderDataTableItem
            ? _FolderContent(name: item.name)
            : _TypeContent(item: item),
      ),
    );
  }
}

class _FolderContent extends StatelessWidget {
  const _FolderContent({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final tokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    return ColoredBox(
      key: const ValueKey('gallery-folder-tile'),
      color: tokens.containerL2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ArDriveSpacing.md),
        child: Row(
          children: [
            ArDriveIcons.folderFilled(size: 20, color: tokens.iconMid),
            const SizedBox(width: ArDriveSpacing.sm),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: typography.paragraphNormal(
                  color: tokens.textHigh,
                  fontWeight: ArFontWeight.semiBold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeContent extends StatelessWidget {
  const _TypeContent({required this.item});

  final ArDriveDataTableItem item;

  @override
  Widget build(BuildContext context) {
    final tokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final small = constraints.maxHeight < 110;
      return ColoredBox(
        key: const ValueKey('gallery-type-tile'),
        // One step closer to the page than a photo's skeleton: a quiet tile.
        color: tokens.containerL1,
        child: Padding(
          padding: const EdgeInsets.all(ArDriveSpacing.xs),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // copyWith: getIconForContentType only honours a colour for
              // some types.
              getIconForContentType(
                item.contentType,
                size: small ? 20 : 28,
              ).copyWith(color: tokens.iconLow),
              const SizedBox(height: ArDriveSpacing.xs),
              Text(
                item.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: typography.caption(color: tokens.textMid),
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// The tile's menu button: the same menu as the list's row. Items are built
/// here, so only a tile that shows its button pays for them.
class _TileMenu extends StatelessWidget {
  const _TileMenu({
    required this.item,
    required this.drive,
    required this.controller,
    required this.onOpenChanged,
  });

  final ArDriveDataTableItem item;
  final Drive drive;
  final ArDriveDropdownController controller;
  final ValueChanged<bool> onOpenChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = ArDriveTheme.of(context).themeData.colorTokens;
    final height =
        MediaQuery.sizeOf(context).width < galleryPhoneBreakpoint ? 44.0 : 48.0;
    return Semantics(
      label: appLocalizationsOf(context).showMenu,
      button: true,
      child: ArDriveDropdown(
        controller: controller,
        onOpenChanged: onOpenChanged,
        height: height,
        anchor: const Aligned(
          follower: Alignment.topRight,
          target: Alignment.bottomRight,
          offset: Offset(0, ArDriveSpacing.xxs),
        ),
        calculateVerticalAlignment: (opensUp) =>
            opensUp ? Alignment.bottomRight : Alignment.topRight,
        items: explorerRowMenuItems(
          context,
          item: item,
          drive: drive,
          height: height,
        ),
        child: Padding(
          padding: const EdgeInsets.all(ArDriveSpacing.xs),
          child: ArDriveIcons.kebabMenu(size: 16, color: tokens.iconHigh),
        ),
      ),
    );
  }
}
