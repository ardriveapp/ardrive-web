import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/gallery/explorer/gallery_item_tile.dart';
import 'package:ardrive/gallery/explorer/gallery_model.dart';
import 'package:ardrive/gallery/explorer/gallery_selection.dart';
import 'package:ardrive/gallery/image_loader/gallery_image_loader.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/pages/drive_detail/models/drive_table_columns.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
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

  @override
  void initState() {
    super.initState();
    _controller =
        ArDriveSectionedGalleryController(scroll: widget.scrollController);
    _controller.scroll.addListener(_scrolled);
    HardwareKeyboard.instance.addHandler(_onEscape);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onEscape);
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
    cubit.openDataItem(item);
  }

  void _longPress(ArDriveDataTableItem item) {
    if (widget.lockMultiSelect) return;
    _anchor = item;
    context.read<DriveDetailCubit>().selectItems([item]);
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
          chosen: month.items.where(_isSelected).length,
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

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: Stack(
        children: [
          Positioned.fill(
            child: ArDriveSectionedGallery(
              controller: _controller,
              sections: sections,
              isPhone: phone,
              padding: EdgeInsets.only(
                left: phone ? galleryPhoneGutter : 0,
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
                Text(
                  widget.title,
                  style: typography.paragraphLarge(
                    color: tokens.textHigh,
                    fontWeight: ArFontWeight.bold,
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
