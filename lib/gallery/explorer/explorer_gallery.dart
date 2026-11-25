import 'dart:async';
import 'dart:math' as math;

import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/gallery/explorer/gallery_item_tile.dart';
import 'package:ardrive/gallery/explorer/gallery_model.dart';
import 'package:ardrive/gallery/explorer/gallery_selection.dart';
import 'package:ardrive/gallery/explorer/gallery_tile_size.dart';
import 'package:ardrive/gallery/image_loader/gallery_image_loader.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/full_screen_preview_request.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/pages/drive_detail/models/drive_table_columns.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/constants.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// A folder's contents as a photo gallery: folders first as small tiles, then
/// the files in months, photos in justified rows, with a timeline on the right
/// for a long folder.
///
/// It is another view of the explorer's list, not another explorer. The rows
/// are the list's (hidden items already filtered out), in the list's sort
/// ([buildGalleryModel]); a click selects and a double-click, touch tap or
/// Enter opens, through the same [DriveDetailCubit] calls the table makes;
/// Shift and Ctrl or Cmd build the same multi-selection, so the bar's bulk
/// actions work unchanged; and a tile's menu is the row's menu
/// ([explorerRowMenuItems]).
class ExplorerGallery extends StatefulWidget {
  const ExplorerGallery({
    super.key,
    required this.items,
    required this.drive,
    required this.folderId,
    required this.selectedItem,
    required this.multiSelected,
    this.sortColumn,
    this.sortOrder,
    this.lockMultiSelect = false,
    this.scrollController,
  });

  /// The folder's visible rows, in the cubit's order.
  final List<ArDriveDataTableItem> items;
  final Drive drive;
  final String folderId;
  final ArDriveDataTableItem? selectedItem;

  /// The multi-selection, empty when none.
  final List<ArDriveDataTableItem> multiSelected;

  /// The column the reader sorted this folder by in the list, if they did.
  final int? sortColumn;
  final TableSort? sortOrder;

  /// A sync is holding multi-select shut, as it does the list's.
  final bool lockMultiSelect;
  final ScrollController? scrollController;

  @override
  State<ExplorerGallery> createState() => _ExplorerGalleryState();
}

class _ExplorerGalleryState extends State<ExplorerGallery> {
  late final ArDriveSectionedGalleryController _controller;
  final _nodes = <String, FocusNode>{};
  ArDriveDataTableItem? _anchor;

  GalleryModel? _model;
  List<ArDriveDataTableItem>? _modelItems;
  Object? _modelKey;
  List<ArDriveDataTableItem> _flat = const [];
  Map<String, int> _indexOf = const {};

  /// The phone's tile size, an index into [galleryPhoneRowHeights].
  int _phoneSize = GalleryPhoneTileSize.read();

  /// The gallery's left padding, so a point on screen finds its tile.
  double _paddingLeft = 0;

  /// Every pointer down on the gallery, where it is now; touches pinch.
  final _pointers = <int, ({Offset at, PointerDeviceKind kind})>{};

  /// The fingers' spread when the pinch began or last changed size.
  double? _pinchFrom;

  /// A second finger came down in this gesture: a pinch, so a long press
  /// that fires anyway (fingers held still) selects nothing. Cleared when
  /// the next gesture starts, not when the fingers lift, since the long
  /// press can be reported after them.
  bool _pinched = false;

  /// The tile a size change keeps under the fingers, and where on it.
  ({int index, double fy, double y})? _hold;

  /// The finger a long press started selecting with, while it drags.
  int? _dragPointer;
  int _dragFrom = 0;
  int? _dragLast;
  List<ArDriveDataTableItem> _dragBase = const [];
  Timer? _autoScroll;

  @override
  void initState() {
    super.initState();
    _controller =
        ArDriveSectionedGalleryController(scroll: widget.scrollController);
    _controller.scroll.addListener(_scrolled);
    _controller.addListener(_laidOut);
    HardwareKeyboard.instance.addHandler(_onEscape);
  }

  @override
  void dispose() {
    _autoScroll?.cancel();
    HardwareKeyboard.instance.removeHandler(_onEscape);
    _controller.removeListener(_laidOut);
    _controller.scroll.removeListener(_scrolled);
    // The scroll controller belongs to the caller when it gave one.
    _controller.dispose();
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  GalleryImageLoader get _loader => context.read<GalleryImageLoader>();

  /// Scrolling, including the timeline's, tells the loader to hold new work
  /// until it rests.
  void _scrolled() => _loader.notifyScrolling();

  FocusNode _nodeFor(ArDriveDataTableItem item) =>
      _nodes.putIfAbsent(item.id, () => FocusNode(debugLabel: item.name));

  GalleryModel _modelFor(AppLocalizations l10n) {
    final key = Object.hash(
        widget.sortColumn, widget.sortOrder, Localizations.localeOf(context));
    final cached = _model;
    if (cached != null &&
        _modelKey == key &&
        _sameObjects(_modelItems!, widget.items)) {
      return cached;
    }
    _modelKey = key;
    _modelItems = widget.items;
    final model = buildGalleryModel(
      widget.items,
      sortColumn: widget.sortColumn,
      sortOrder: widget.sortOrder,
      typeLabel: (item) => driveTableTypeLabel(
        l10n,
        driveTableType(contentType: item.contentType, name: item.name),
      ),
    );
    _model = model;
    _flat = model.flat;
    _indexOf = {for (var i = 0; i < _flat.length; i++) _flat[i].id: i};
    // Focus nodes of items that are gone go with them, after this frame.
    final ids = _indexOf.keys.toSet();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final gone = _nodes.keys.where((id) => !ids.contains(id)).toList();
      for (final id in gone) {
        _nodes.remove(id)?.dispose();
      }
    });
    return model;
  }

  static bool _sameObjects(
    List<ArDriveDataTableItem> a,
    List<ArDriveDataTableItem> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  bool _isSelected(ArDriveDataTableItem item) => widget.multiSelected.isNotEmpty
      ? widget.multiSelected.any((e) => e.id == item.id)
      : widget.selectedItem?.id == item.id;

  void _click(ArDriveDataTableItem item, GalleryClickKind kind) {
    _nodeFor(item).requestFocus();
    // A sync that holds multi-select shut holds it here too: a modifier then
    // is just a click.
    final effective = widget.lockMultiSelect ? GalleryClickKind.plain : kind;
    final change = resolveGalleryClick(
      item: item,
      kind: effective,
      ordered: _flat,
      multiSelected: widget.multiSelected,
      selected: widget.selectedItem,
      anchor: _anchor,
    );
    _anchor = change.anchor;
    final cubit = context.read<DriveDetailCubit>();
    final many = change.selectMany;
    if (many != null) cubit.selectItems(many);
    final one = change.select;
    if (one != null) cubit.selectDataItem(one, openDetails: false);
  }

  void _open(ArDriveDataTableItem item) {
    final cubit = context.read<DriveDetailCubit>();
    // Once a finger has started selecting, a tap adds to the selection, as
    // in the photo apps; it opens again when nothing is chosen.
    final phone = galleryScreenIsPhone(context);
    if (phone && widget.multiSelected.isNotEmpty && !widget.lockMultiSelect) {
      _click(item, GalleryClickKind.toggle);
      return;
    }
    // A photo opens to full screen, as in a photo app; closing it comes
    // back to the grid. Anything else opens in the details panel as before.
    if (item is FileDataTableItem &&
        supportedImageTypesInFilePreview.contains(item.contentType)) {
      // Not tied to this widget: on a phone the details page takes the
      // gallery's place while the photo is open.
      FullScreenPreviewRequest.request(
          fileId: item.id,
          onClosed: () {
            if (!cubit.isClosed) cubit.closeDetails();
          });
    }
    cubit.openDataItem(item);
  }

  void _longPress(ArDriveDataTableItem item) {
    if (widget.lockMultiSelect || _pinched || _pointers.length > 1) return;
    _anchor = item;
    // While selecting on a phone, a long press adds, as a tap does; it
    // starts a new selection otherwise.
    final base = galleryScreenIsPhone(context)
        ? [
            for (final e in widget.multiSelected)
              if (e.id != item.id) e
          ]
        : const <ArDriveDataTableItem>[];
    context.read<DriveDetailCubit>().selectItems([...base, item]);
    // The finger that pressed can now drag across tiles to add them.
    final index = _indexOf[item.id];
    if (_pointers.length == 1 && index != null) {
      _dragPointer = _pointers.keys.single;
      _dragFrom = index;
      _dragLast = index;
      _dragBase = base;
      _autoScroll?.cancel();
      _autoScroll = Timer.periodic(
          const Duration(milliseconds: 16), (_) => _autoScrollTick());
    }
  }

  /// A point on the gallery, in its layout's coordinates.
  Offset _contentPoint(Offset local) => Offset(
        local.dx - _paddingLeft,
        local.dy +
            (_controller.scroll.hasClients
                ? _controller.scroll.position.pixels
                : 0),
      );

  void _pointerDown(PointerDownEvent event) {
    if (_pointers.isEmpty) _pinched = false;
    _pointers[event.pointer] = (at: event.localPosition, kind: event.kind);
    final touches = _touches();
    if (touches.length >= 2) _pinched = true;
    if (touches.length == 2 && galleryScreenIsPhone(context)) {
      // A second finger: a pinch, not a scroll or a drag across tiles.
      _endDrag();
      _stopScrolling();
      _pinchFrom = _spread(touches);
    }
  }

  void _pointerMove(PointerMoveEvent event) {
    final down = _pointers[event.pointer];
    if (down == null) return;
    _pointers[event.pointer] = (at: event.localPosition, kind: down.kind);
    if (event.pointer == _dragPointer) _dragTo(event.localPosition);
    final from = _pinchFrom;
    final touches = _touches();
    if (from == null || touches.length != 2) return;
    _stopScrolling();
    final spread = _spread(touches);
    // A quarter wider or narrower moves one size, as far as there is one.
    final step = spread > from * 1.25
        ? 1
        : spread < from * 0.8
            ? -1
            : 0;
    if (step == 0) return;
    _pinchFrom = spread;
    final next =
        (_phoneSize + step).clamp(0, galleryPhoneRowHeights.length - 1);
    if (next == _phoneSize) return;
    _holdUnder((touches[0] + touches[1]) / 2);
    setState(() => _phoneSize = next);
    GalleryPhoneTileSize.write(next);
  }

  void _pointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (event.pointer == _dragPointer) _endDrag();
    if (_touches().length < 2) _pinchFrom = null;
  }

  List<Offset> _touches() => [
        for (final p in _pointers.values)
          if (p.kind == PointerDeviceKind.touch) p.at,
      ];

  /// Fingers that start almost together count as a little apart, so the
  /// first movement is not read as a huge pinch.
  static double _spread(List<Offset> touches) =>
      math.max(32, (touches[0] - touches[1]).distance);

  /// A pinch holds the list still: the second finger can have started a
  /// scroll with the first.
  void _stopScrolling() {
    if (!_controller.scroll.hasClients) return;
    final position = _controller.scroll.position;
    if (position.isScrollingNotifier.value) position.jumpTo(position.pixels);
  }

  /// Notes the tile under [local] and how far down it the point is, so the
  /// new layout can put that spot back under the fingers.
  void _holdUnder(Offset local) {
    final geometry = _controller.geometry;
    if (geometry == null) return;
    final point = _contentPoint(local);
    final index = geometry.itemNear(point);
    final rect = index == null ? null : geometry.rectOf(index);
    if (index == null || rect == null) return;
    _hold = (
      index: index,
      fy: ((point.dy - rect.top) / rect.height).clamp(0.0, 1.0),
      y: local.dy,
    );
  }

  /// The new layout is in: scrolls so the held tile is where it was.
  void _laidOut() {
    final hold = _hold;
    final geometry = _controller.geometry;
    if (hold == null || geometry == null || !_controller.scroll.hasClients) {
      return;
    }
    _hold = null;
    final rect = geometry.rectOf(hold.index);
    if (rect == null) return;
    final position = _controller.scroll.position;
    position.jumpTo((rect.top + hold.fy * rect.height - hold.y)
        .clamp(position.minScrollExtent, position.maxScrollExtent));
  }

  /// Every tile from the long-pressed one to the one under the finger, on
  /// top of what was chosen before; going back takes tiles out again.
  void _dragTo(Offset local) {
    final geometry = _controller.geometry;
    if (geometry == null) return;
    // The nearest tile, so a finger over a gap or a month's header keeps
    // the selection where it is rather than dropping out of it.
    final index = geometry.itemNear(_contentPoint(local));
    if (index == null || index == _dragLast || index >= _flat.length) return;
    _dragLast = index;
    final ids = {for (final e in _dragBase) e.id};
    final range = _flat.sublist(
        math.min(_dragFrom, index), math.max(_dragFrom, index) + 1);
    context.read<DriveDetailCubit>().selectItems(
        [..._dragBase, ...range.where((e) => !ids.contains(e.id))]);
  }

  /// Near the top or bottom edge, the list scrolls under a dragging finger,
  /// faster the nearer it is, and the tiles it passes are taken in.
  void _autoScrollTick() {
    final pointer = _dragPointer;
    final at = pointer == null ? null : _pointers[pointer]?.at;
    if (at == null || !_controller.scroll.hasClients) return;
    final position = _controller.scroll.position;
    const edge = 56.0;
    const fastest = 14.0;
    final height = position.viewportDimension;
    double speed = 0;
    if (at.dy < edge) {
      speed = -fastest * (edge - at.dy) / edge;
    } else if (at.dy > height - edge) {
      speed = fastest * (at.dy - (height - edge)) / edge;
    }
    if (speed == 0) return;
    final target = (position.pixels + speed)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target == position.pixels) return;
    position.jumpTo(target);
    _dragTo(at);
  }

  void _endDrag() {
    _dragPointer = null;
    _dragLast = null;
    _autoScroll?.cancel();
    _autoScroll = null;
  }

  /// A month's control: the whole month in, or out when it is all in.
  void _toggleMonth(GalleryMonth month) {
    if (widget.lockMultiSelect) return;
    _anchor = null;
    context.read<DriveDetailCubit>().selectItems(resolveMonthToggle(
          month: month.items,
          multiSelected: widget.multiSelected,
        ));
  }

  int _chosenIn(GalleryMonth month) {
    final chosen = {for (final e in widget.multiSelected) e.id};
    return month.items.where((e) => chosen.contains(e.id)).length;
  }

  void _selectForMenu(ArDriveDataTableItem item) {
    if (_isSelected(item)) return;
    _click(item, GalleryClickKind.plain);
  }

  /// Escape ends a multi-selection, as it does the list's.
  bool _onEscape(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !mounted ||
        ModalRoute.of(context)?.isCurrent == false ||
        widget.multiSelected.isEmpty) {
      return false;
    }
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus != null &&
        (focus.widget is EditableText ||
            focus.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return false;
    }
    _anchor = null;
    context.read<DriveDetailCubit>().selectItems(const []);
    return true;
  }

  int? _focusedIndex() {
    for (final entry in _nodes.entries) {
      if (entry.value.hasPrimaryFocus) return _indexOf[entry.key];
    }
    return null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => GalleryDirection.left,
      LogicalKeyboardKey.arrowRight => GalleryDirection.right,
      LogicalKeyboardKey.arrowUp => GalleryDirection.up,
      LogicalKeyboardKey.arrowDown => GalleryDirection.down,
      _ => null,
    };
    final geometry = _controller.geometry;
    final current = _focusedIndex();
    if (direction == null || geometry == null || current == null) {
      return KeyEventResult.ignored;
    }
    final next = geometry.neighbour(current, direction);
    if (next != null) {
      _controller.ensureVisible(next);
      // A tile that is not built yet takes focus when it is.
      _nodeFor(_flat[next]).requestFocus();
    }
    return KeyEventResult.handled;
  }

  String _monthTitle(GalleryMonth month) {
    final date = DateTime(month.year, month.month);
    final locale = Localizations.localeOf(context).toLanguageTag();
    try {
      return DateFormat.yMMMM(locale).format(date);
    } catch (_) {
      return DateFormat.yMMMM('en').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = appLocalizationsOf(context);
    final model = _modelFor(l10n);
    final phone = galleryScreenIsPhone(context);

    final sections = <ArDriveGallerySection>[];
    final entries = <ArDriveGalleryScrubberEntry>[];
    if (model.folders.isNotEmpty) {
      sections.add(ArDriveGallerySection(
        key: 'folders',
        itemCount: model.folders.length,
        targetRowHeight: galleryFolderRowHeight,
      ));
    }
    int? lastYear;
    for (final month in model.months) {
      final title = _monthTitle(month);
      entries.add(ArDriveGalleryScrubberEntry(
        section: sections.length,
        title: title,
        tick: month.year == lastYear ? null : '${month.year}',
      ));
      lastYear = month.year;
      sections.add(ArDriveGallerySection(
        key: month.id,
        itemCount: month.items.length,
        header: _MonthHeader(
          title: title,
          count: l10n.galleryItemCount(month.items.length),
          selectLabel: l10n.gallerySelectMonth(title),
          // The multi-selection only, as the control acts on it: a single
          // selected photo is not ticked into its month.
          chosen: _chosenIn(month),
          total: month.items.length,
          alwaysShowControl: phone,
          onToggle: widget.lockMultiSelect ? null : () => _toggleMonth(month),
        ),
      ));
    }

    final folderCount = model.folders.length;
    final trackWidth = phone
        ? ArDriveGalleryScrubber.phoneWidth
        : ArDriveGalleryScrubber.defaultWidth;
    _paddingLeft = phone ? galleryPhoneGutter : 0;

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: Stack(
        children: [
          Positioned.fill(
            // Raw pointers, beside the tiles' own gestures: a pinch changes
            // the phone's tile size, and a finger that long-pressed drags
            // across tiles to choose them.
            child: Listener(
              onPointerDown: _pointerDown,
              onPointerMove: _pointerMove,
              onPointerUp: _pointerUp,
              onPointerCancel: _pointerUp,
              child: ArDriveSectionedGallery(
                controller: _controller,
                sections: sections,
                isPhone: phone,
                targetRowHeight:
                    phone ? galleryPhoneRowHeights[_phoneSize] : null,
                padding: EdgeInsets.only(
                  left: _paddingLeft,
                  right: phone ? galleryPhoneGutter : trackWidth,
                  bottom: ArDriveSpacing.md,
                ),
                layoutRevision: Object.hashAll(_flat.map((e) => e.id)),
                aspectRatioOf: (i) => i < folderCount
                    ? (phone
                        ? galleryFolderAspectRatioPhone
                        : galleryFolderAspectRatio)
                    : galleryAspectRatioOf(_flat[i]),
                itemKeyOf: (i) => ValueKey(_flat[i].id),
                tileBuilder: (context, i, size) {
                  final item = _flat[i];
                  return GalleryItemTile(
                    item: item,
                    drive: widget.drive,
                    size: size,
                    selected: _isSelected(item),
                    focusNode: _nodeFor(item),
                    loader: _loader,
                    onClick: (kind) => _click(item, kind),
                    onOpen: () => _open(item),
                    onSelectForMenu: () => _selectForMenu(item),
                    onLongPress: () => _longPress(item),
                  );
                },
              ),
            ),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            child: ArDriveGalleryScrubber(
              controller: _controller,
              entries: entries,
              width: trackWidth,
              semanticLabel: l10n.galleryTimeline,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthHeader extends StatefulWidget {
  const _MonthHeader({
    required this.title,
    required this.count,
    required this.selectLabel,
    required this.chosen,
    required this.total,
    required this.alwaysShowControl,
    required this.onToggle,
  });

  final String title;
  final String count;
  final String selectLabel;
  final int chosen;
  final int total;
  final bool alwaysShowControl;

  /// Null when a sync holds multi-select shut: there is no control then.
  final VoidCallback? onToggle;

  @override
  State<_MonthHeader> createState() => _MonthHeaderState();
}

class _MonthHeaderState extends State<_MonthHeader> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final all = widget.total > 0 && widget.chosen == widget.total;
    final some = widget.chosen > 0;
    final onToggle = widget.onToggle;
    final showControl =
        onToggle != null && (widget.alwaysShowControl || _hovered || some);

    return Semantics(
      header: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Align(
          alignment: AlignmentDirectional.bottomStart,
          child: Padding(
            padding: const EdgeInsets.only(bottom: ArDriveSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: typography.paragraphLarge(
                      color: tokens.textHigh,
                      fontWeight: ArFontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: ArDriveSpacing.sm),
                Text(widget.count,
                    style: typography.caption(color: tokens.textLow)),
                if (onToggle != null) ...[
                  const SizedBox(width: ArDriveSpacing.xs),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: showControl
                        ? Semantics(
                            key: const ValueKey('gallery-month-select'),
                            button: true,
                            checked: all,
                            label: widget.selectLabel,
                            excludeSemantics: true,
                            onTap: onToggle,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: onToggle,
                              child: Center(
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: all
                                        ? tokens.buttonPrimaryDefault
                                        : null,
                                    border: all
                                        ? null
                                        : Border.all(
                                            color: some
                                                ? tokens.strokeHigh
                                                : tokens.strokeMid,
                                            width: 2,
                                          ),
                                  ),
                                  child: all
                                      ? ArDriveIcons.checkmark(
                                          size: 12,
                                          color: tokens.textOnPrimary,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          )
                        : null,
                  )
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
