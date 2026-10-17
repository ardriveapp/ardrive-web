import 'dart:async';
import 'dart:math';

import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_ui/src/styles/colors/global_colors.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

class TableColumn {
  TableColumn(
    this.title,
    this.size, {
    required this.index,
    this.isVisible = true,
    this.canHide = true,
    this.textStyle,
  });

  final String title;
  final int size;
  final bool isVisible;
  final int index;
  final bool canHide;
  final TextStyle? textStyle;
}

class TableRowWidget {
  TableRowWidget(this.row);

  final List<Widget> row;
}

class ArDriveDataTable<T extends IndexedItem> extends StatefulWidget {
  final List<TableColumn> columns;
  final List<T> rows;
  final TableRowWidget Function(T row) buildRow;
  final Widget Function(T row)? leading;
  final Widget Function(T row)? trailing;
  final int Function(T a, T b) Function(int columnIndex)? sort;
  final List<T> Function(List<T> rows, int columnIndex, TableSort sortOrder)?
      sortRows;

  /// Called with the zero-based page whenever the page on screen changes,
  /// including the page a [revealRow] lands on when the table is built.
  final Function(int page)? onChangePage;

  /// How many rows a page holds. Defaults to the first of
  /// [rowsPerPageOptions]. The table applies a choice from its own picker at
  /// once and reports it with [onRowsPerPageChanged]; a new value passed in
  /// later is applied too, keeping the first row on screen in view.
  final int? rowsPerPage;

  /// The sizes the rows-per-page picker offers, smallest first. The footer is
  /// only shown when there are more rows than the smallest of them.
  final List<int> rowsPerPageOptions;
  final void Function(int rowsPerPage)? onRowsPerPageChanged;
  final String rowsPerPageText;

  /// The footer's "1-25 of 312". Given the one-based first and last row on
  /// screen and the total.
  final String Function(int first, int last, int total)? pageRangeText;
  final String previousPageText;
  final String nextPageText;

  /// What a screen reader says for a page button, given the one-based page.
  final String Function(int page)? pageText;
  final Function(List<MultiSelectBox<T>> selectedRows)? onSelectedRows;
  final Function(T row)? onRowTap;

  /// Opening a row, as a file manager means it: a double-click, a single tap
  /// on a touch screen, or Enter on the selected row.
  ///
  /// When this is given, a click only selects - [onRowTap] - and opening is a
  /// separate act. Without it the table behaves as it always has, so the
  /// dialogs that draw one to pick a row are unaffected.
  final void Function(T row)? onRowOpen;
  final Function(bool onChangeMultiSelecting)? onChangeMultiSelecting;
  final bool forceDisableMultiSelect;
  final bool lockMultiSelect;
  final T? selectedRow;
  final Function(TableColumn)? onChangeColumnVisibility;

  /// The zero-based page to open on, clamped to the pages there are.
  final int? initialPage;

  /// A row to open on: when the table is built, the page holding it is shown
  /// instead of [initialPage], and reported through [onChangePage].
  final T? revealRow;

  /// Where the list starts scrolled to when the table is built, for a table
  /// rebuilt in place. Applied only to the page [initialPage] chose.
  final double? initialScrollOffset;

  /// Called as the list scrolls with how far it is scrolled, so the next
  /// table built for the same rows can be given it back. Reported as it
  /// happens rather than as the table is taken down, because a table rebuilt
  /// in place - after a sync - is built before the old one is taken down.
  final void Function(double offset)? onScrollOffsetSaved;

  const ArDriveDataTable({
    super.key,
    required this.columns,
    required this.buildRow,
    required this.rows,
    this.leading,
    this.trailing,
    this.sort,
    this.onChangePage,
    this.rowsPerPage,
    this.rowsPerPageOptions = const [25, 50, 100],
    this.onRowsPerPageChanged,
    required this.rowsPerPageText,
    this.pageRangeText,
    this.previousPageText = 'Previous page',
    this.nextPageText = 'Next page',
    this.pageText,
    this.sortRows,
    this.onSelectedRows,
    this.onRowTap,
    this.onRowOpen,
    this.onChangeMultiSelecting,
    this.forceDisableMultiSelect = false,
    this.lockMultiSelect = false,
    this.selectedRow,
    this.onChangeColumnVisibility,
    this.initialPage,
    this.revealRow,
    this.initialScrollOffset,
    this.onScrollOffsetSaved,
  });

  @override
  State<ArDriveDataTable> createState() => _ArDriveDataTableState<T>();
}

enum TableSort { asc, desc }

abstract class IndexedItem extends Equatable {
  const IndexedItem(this.index);

  final int index;
}

class _ArDriveDataTableState<T extends IndexedItem>
    extends State<ArDriveDataTable<T>> {
  late List<T> _cachedRows;
  late List<T> _currentPage;
  final List<MultiSelectBox<T>> _multiSelectBoxes = [];
  T? _selectedItem;
  List<TableColumn> _columns = [];

  /// A copy of the columns the caller last passed. A copy, because a caller
  /// that changes its list in place passes the same list again, and the old
  /// widget's list would already hold the change.
  List<TableColumn> _callerColumns = [];

  late final ScrollController _scrollController;

  /// A row [ArDriveDataTable.revealRow] opened on, until it is scrolled into
  /// view: its page is shown from the top, and the row can be below the fold.
  T? _scrollToRow;
  final _scrollToRowKey = GlobalKey(debugLabel: 'revealed row');

  late int _selectedPage;
  late int _numberOfItemsPerPage;
  int? _sortedColumn;
  bool _isMultiSelectingWithLongPress = false;

  TableSort? _tableSort;

  bool _isCtrlPressed = false;

  /// The pointer behind the tap being handled, read on the way down. Null
  /// when the tap came from no pointer at all - Enter or Space on a focused
  /// row, or a screen reader - and those open, since opening is what they ask
  /// for.
  PointerDeviceKind? _tapKind;

  final _doubleClick = ArDriveDoubleClick<T>();

  /// Where Enter is heard. A click on a row puts focus here, so Enter opens
  /// the row just clicked even if the search box had focus a moment before,
  /// and a button focused anywhere else keeps Enter for itself.
  final _focusNode = FocusNode(debugLabel: 'ArDriveDataTable');
  int? _shiftSelectionStartIndex;

  bool get _isMultiSelecting {
    final isMultiSelecting = _isMultiSelectingWithLongPress ||
        _multiSelectBoxes.isNotEmpty &&
            _multiSelectBoxes
                .any((element) => element.selectedItems.isNotEmpty) ||
        _isCtrlPressed;

    return isMultiSelecting;
  }

  @override
  void initState() {
    super.initState();
    _cachedRows = widget.rows;
    _numberOfItemsPerPage = _validRowsPerPage(widget.rowsPerPage);

    // The page to open on: the one holding [revealRow] if there is one,
    // otherwise [initialPage]. Clamped, because a page number outlives the
    // rows it was counted against: a folder can shrink between visits.
    final revealIndex =
        widget.revealRow == null ? -1 : _cachedRows.indexOf(widget.revealRow!);
    final revealing = revealIndex >= 0;
    _selectedPage = _clampPage(
      revealing
          ? revealIndex ~/ _numberOfItemsPerPage
          : widget.initialPage ?? 0,
    );

    _scrollController = ScrollController(
      initialScrollOffset: !revealing && widget.initialScrollOffset != null
          ? widget.initialScrollOffset!
          : 0,
    )..addListener(_reportScrollOffset);

    _currentPage = _rowsOfPage(_selectedPage);

    if (widget.revealRow != null) {
      // Told even when the row was not found, so a caller waiting to hear
      // that the reveal was handled is never left waiting.
      final page = _selectedPage;
      _scrollToRow = revealing ? widget.revealRow : null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onChangePage?.call(page);
        _scrollRevealedRowIntoView();
      });
    }

    HardwareKeyboard.instance.addHandler(_handleKeyDownEvent);
    HardwareKeyboard.instance.addHandler(_handleEscapeKey);
    HardwareKeyboard.instance.addHandler(_handleSelectAllShortcut);

    _columns = List.of(widget.columns);
    _callerColumns = List.of(widget.columns);
  }

  // These handlers are global, so without this they outlived the table: the
  // select-all shortcut would go on calling setState on a table the reader had
  // already left.
  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyDownEvent);
    HardwareKeyboard.instance.removeHandler(_handleEscapeKey);
    HardwareKeyboard.instance.removeHandler(_handleSelectAllShortcut);
    _scrollController
      ..removeListener(_reportScrollOffset)
      ..dispose();
    _doubleClick.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _reportScrollOffset() {
    if (_scrollController.hasClients) {
      widget.onScrollOffsetSaved?.call(_scrollController.offset);
    }
  }

  /// Enter opens the selected row, as it does in any file manager.
  ///
  /// Heard only while focus is in the table, which a click on a row puts it.
  /// That rules out, without listing them, every place Enter means something
  /// else: a text field, a dialog, a button focused elsewhere. The table's
  /// other shortcuts are global handlers; this one is not, because Enter is
  /// the key everything else also wants.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final onRowOpen = widget.onRowOpen;
    final selected = _selectedItem;

    if (onRowOpen == null ||
        selected == null ||
        _isMultiSelecting ||
        event is! KeyDownEvent ||
        (event.logicalKey != LogicalKeyboardKey.enter &&
            event.logicalKey != LogicalKeyboardKey.numpadEnter)) {
      return KeyEventResult.ignored;
    }

    // Only a row that is on screen, which means on this page. Entering a
    // folder leaves it as the explorer's selection, so without this Enter
    // would enter the folder the reader is already in, again; and a row
    // chosen on one page is still selected after the reader moves to another.
    if (!_currentPage.contains(selected)) {
      return KeyEventResult.ignored;
    }

    onRowOpen(selected);
    return KeyEventResult.handled;
  }

  /// A plain tap on a row: select it, or open it, or both.
  void _onRowTapped(T row) {
    final kind = _tapKind;
    _tapKind = null;

    final onRowOpen = widget.onRowOpen;

    // A second click on the row a first one just selected: that is a
    // double-click, and it opens. It does not select again on the way.
    if (onRowOpen != null && _doubleClick.completes(row)) {
      onRowOpen(row);
      return;
    }

    setState(() {
      _selectedItem = row;
    });
    widget.onRowTap?.call(row);

    if (onRowOpen == null) {
      return;
    }

    _focusNode.requestFocus();

    if (ArDriveDoubleClick.tapOpens(kind)) {
      _doubleClick.reset();
      onRowOpen(row);
      return;
    }

    _doubleClick.arm(row);
  }

  void openMultiSelectBox() {
    if (!_multiSelectBoxes.any((element) => element.page == _selectedPage)) {
      _multiSelectBoxes.add(
        MultiSelectBox(
          selectedItems: [],
          page: _selectedPage,
        ),
      );
    }
  }

  MultiSelectBox<T> getMultiSelectBox() {
    if (!_multiSelectBoxes.any((element) => element.page == _selectedPage)) {
      openMultiSelectBox();
    }

    return _multiSelectBoxes.firstWhere(
      (element) => element.page == _selectedPage,
    );
  }

  static bool _sameColumns(List<TableColumn> a, List<TableColumn> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i].title != b[i].title ||
          a[i].isVisible != b[i].isVisible ||
          a[i].index != b[i].index ||
          a[i].size != b[i].size) {
        return false;
      }
    }
    return true;
  }

  int _validRowsPerPage(int? rowsPerPage) {
    if (rowsPerPage != null && rowsPerPage > 0) {
      return rowsPerPage;
    }
    return widget.rowsPerPageOptions.isEmpty
        ? 25
        : widget.rowsPerPageOptions.first;
  }

  /// Applies a new page size, keeping the first row on screen in view.
  void _applyRowsPerPage(int newItemsPerPage) {
    if (newItemsPerPage == _numberOfItemsPerPage) {
      return;
    }

    final firstRowOnScreen = _selectedPage * _numberOfItemsPerPage;
    final hadSelection =
        _multiSelectBoxes.any((box) => box.selectedItems.isNotEmpty);

    setState(() {
      _numberOfItemsPerPage = newItemsPerPage;

      // Selections are kept per page, and every page has just changed.
      _multiSelectBoxes.clear();
      _isMultiSelectingWithLongPress = false;
      _shiftSelectionStartIndex = null;
    });

    if (hadSelection) {
      _afterBuild(() => widget.onSelectedRows?.call([]));
    }

    selectPage(firstRowOnScreen ~/ newItemsPerPage);
  }

  /// A size chosen from the footer's picker.
  ///
  /// Reported before it is applied, so a listener that counts pages in rows
  /// already knows the new size when it hears the page that follows.
  void _onRowsPerPageChosen(int newItemsPerPage) {
    widget.onRowsPerPageChanged?.call(newItemsPerPage);
    _applyRowsPerPage(newItemsPerPage);
  }

  void _toggleColumnVisibility(int index) {
    setState(() {
      final column = TableColumn(
        _columns[index].title,
        _columns[index].size,
        isVisible: !_columns[index].isVisible,
        index: _columns[index].index,
      );
      _columns[index] = column;
      widget.onChangeColumnVisibility?.call(column);
    });
  }

  int get _pageCount => _cachedRows.isEmpty
      ? 1
      : (_cachedRows.length / _numberOfItemsPerPage).ceil();

  int _clampPage(int page) => page.clamp(0, _pageCount - 1);

  List<T> _rowsOfPage(int page) {
    final start = page * _numberOfItemsPerPage;
    final end = start + _numberOfItemsPerPage;
    return _cachedRows.sublist(
      start.clamp(0, _cachedRows.length),
      end.clamp(0, _cachedRows.length),
    );
  }

  void clearSelection() {
    widget.onSelectedRows?.call([]);
    _multiSelectBoxes.clear();
    _isMultiSelectingWithLongPress = false;
    _isCtrlPressed = false;
    _shiftSelectionStartIndex = null;
  }

  @override
  void didChangeDependencies() {
    if (mounted) {
      if (getMultiSelectBox().selectedItems.isEmpty) {
        widget.onChangeMultiSelecting!(false);
      }
    }

    super.didChangeDependencies();
  }

  @override
  void didUpdateWidget(oldWidget) {
    super.didUpdateWidget(oldWidget);

    // The columns follow the caller. They were read once, when the table was
    // built, so a column the caller hid as the table narrowed - opening the
    // details panel, or a smaller window - stayed in every row, and the rows
    // squeezed their cells into a letter's width while the header hid it.
    // Only a change in what the caller passes counts: a column the reader
    // hid from the table's own menu stays hidden for a caller that does not
    // pass it back.
    if (!_sameColumns(widget.columns, _callerColumns)) {
      _columns = List.of(widget.columns);
      _callerColumns = List.of(widget.columns);
    }

    if (widget.rowsPerPage != oldWidget.rowsPerPage &&
        widget.rowsPerPage != null) {
      _applyRowsPerPage(_validRowsPerPage(widget.rowsPerPage));
    }

    if (oldWidget != widget) {
      if (widget.selectedRow != _selectedItem) {
        setState(() {
          _selectedItem = widget.selectedRow;
        });
      }

      if (widget.forceDisableMultiSelect && _isMultiSelecting) {
        clearSelection();
      }

      final temp = <T>[];

      final currentMultiSelectBox = getMultiSelectBox();

      // Updates the list of selected rows if the list of rows has changed
      if (_cachedRows.length != widget.rows.length) {
        if (currentMultiSelectBox.selectedItems.isNotEmpty &&
            !widget.lockMultiSelect) {
          for (final row in currentMultiSelectBox.selectedItems) {
            final index = widget.rows.indexWhere((element) => element == row);
            temp.add(widget.rows[index]);
          }

          currentMultiSelectBox.clear();
          currentMultiSelectBox.addAll(temp);
        }

        _cachedRows = widget.rows;

        // The same page, or the last one if the rows it showed are gone.
        selectPage(_selectedPage);
      } else {
        if (_sortedColumn != null) {
          _sortRows(_sortedColumn!);
        }
      }
    }
  }

  bool _handleEscapeKey(KeyEvent event) {
    if (mounted) {
      if (HardwareKeyboard.instance
          .isLogicalKeyPressed(LogicalKeyboardKey.escape)) {
        setState(() {
          clearSelection();

          if (widget.onChangeMultiSelecting != null) {
            widget.onChangeMultiSelecting!(false);
          }
        });
        return true;
      }
    }
    return false;
  }

  /// Selects all items c=with ctrl / command + a
  bool _handleSelectAllShortcut(KeyEvent event) {
    if (HardwareKeyboard.instance
            .isLogicalKeyPressed(LogicalKeyboardKey.keyA) &&
        _isCtrlPressed) {
      _selectAllItemsInPage();
      return true;
    }
    return false;
  }

  bool _handleKeyDownEvent(KeyEvent event) {
    if (mounted && !widget.lockMultiSelect) {
      if (AppPlatform.isWindows()) {
        setState(() {
          _isCtrlPressed = HardwareKeyboard.instance.isControlPressed;
          widget.onChangeMultiSelecting!(_isMultiSelecting);
        });
      } else if (widget.onChangeMultiSelecting != null) {
        setState(() {
          _isCtrlPressed = HardwareKeyboard.instance.isMetaPressed;
          widget.onChangeMultiSelecting!(_isMultiSelecting);
        });
      }
    }
    return false;
  }

  void _selectMultiSelectItem(T item, int index, bool select) {
    if (widget.lockMultiSelect) {
      return;
    }

    setState(() {
      if (!_multiSelectBoxes.any((element) => element.page == _selectedPage)) {
        _multiSelectBoxes.add(
          MultiSelectBox(
            selectedItems: [],
            page: _selectedPage,
          ),
        );
      }

      final multiselectBox = getMultiSelectBox();

      if (_isCtrlPressed) {
        if (multiselectBox.selectedItems.contains(item)) {
          multiselectBox.remove(item);
        } else {
          multiselectBox.add(item);
        }
      } else if (HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.shiftLeft)) {
        if (_shiftSelectionStartIndex != null) {
          final startIndex = _shiftSelectionStartIndex!;
          final endIndex = index;
          final start = startIndex < endIndex ? startIndex : endIndex;
          final end = startIndex > endIndex ? startIndex : endIndex;
          multiselectBox.selectedItems.clear();

          for (int i = start; i <= end; i++) {
            multiselectBox.add(_currentPage[i]);
          }
        } else {
          _shiftSelectionStartIndex = index;
          multiselectBox.selectedItems.clear();
          multiselectBox.add(item);
        }
      } else {
        _shiftSelectionStartIndex = null;
        if (select) {
          multiselectBox.add(item);
        } else {
          multiselectBox.remove(item);
        }
      }
    });

    widget.onSelectedRows?.call(_multiSelectBoxes);
  }

  void _selectAllItemsInPage() {
    if (widget.lockMultiSelect) {
      return;
    }

    final multiselectPage = getMultiSelectBox();

    setState(() {
      multiselectPage.addAll(_currentPage);
    });

    widget.onSelectedRows?.call(_multiSelectBoxes);
  }

  @override
  Widget build(BuildContext context) {
    final columns = List.generate(
      _columns.length,
      (index) => _buildSingleColumn(
        column: _columns[index],
        index: index,
      ),
      growable: false,
    );

    EdgeInsets getPadding() {
      double rightPadding = 0;
      double leftPadding = 0;

      if (widget.leading != null) {
        leftPadding = 60;
      } else {
        leftPadding = 20;
      }
      if (widget.trailing != null) {
        rightPadding = 20;
      } else {
        rightPadding = 20;
      }

      return EdgeInsets.only(left: leftPadding, right: rightPadding);
    }

    // Focus lives on the whole table, not a row: a click on any row brings
    // Enter here, and the row it opens is whichever one is selected.
    return Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        child: ArDriveCard(
          backgroundColor:
              ArDriveTheme.of(context).themeData.tableTheme.backgroundColor,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          key: widget.key,
          content: Column(
            children: [
              // The same air the drives list puts above its headings: 8 of
              // panel padding and 6 of the header's own. It was 28 here, which
              // is why one table looked roomier than the other on screens a
              // reader moves between.
              const SizedBox(
                height: 14,
              ),
              Row(
                children: [
                  _masterMultiselectCheckBox(),
                  Flexible(
                    child: AnimatedPadding(
                      duration: const Duration(milliseconds: 300),
                      padding: getPadding(),
                      child: Row(
                        children: [
                          ...columns,
                          const SizedBox(
                            width: 90,
                          ),
                          ArDriveSubmenu(
                            alignmentOffset: const Offset(-150, 10),
                            menuChildren: [
                              for (int i = 0; i < _columns.length; i++)
                                ArDriveSubmenuItem(
                                    widget: Padding(
                                  padding: EdgeInsets.only(
                                      top: (i == 0) ? 16 : 8,
                                      left: 16,
                                      right: 16,
                                      bottom:
                                          (i == _columns.length - 1) ? 16 : 8),
                                  child: ArDriveCheckBox(
                                    isDisabled: !_columns[i].canHide,
                                    title: _columns[i].title,
                                    checked: _columns[i].isVisible,
                                    titleStyle: ArDriveTypography.body
                                        .buttonLargeBold(),
                                    onChange: (value) {
                                      _toggleColumnVisibility(i);
                                    },
                                  ),
                                ))
                            ],
                            child: ArDriveIcons.plus(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              // And the same 6 beneath them before the first row, where the
              // gap was 25: four times the drives list, and the half of it a
              // reader actually notices.
              const SizedBox(
                height: 6,
              ),
              Expanded(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height,
                  ),
                  child: ArDriveScrollBar(
                    controller: _scrollController,
                    child: ListView.builder(
                      controller: _scrollController,
                      itemCount: _currentPage.length,
                      itemBuilder: (context, index) {
                        return ArDriveClickArea(
                          key: ValueKey(_currentPage[index]),
                          child: _HoverableRow(
                            key: _currentPage[index] == _scrollToRow
                                ? _scrollToRowKey
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: _buildRowSpacing(
                                _columns,
                                widget.buildRow(_currentPage[index]).row,
                                _currentPage[index],
                                index,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              _pageIndicator(),
            ],
          ),
        ));
  }

  Widget _buildSingleColumn({required TableColumn column, required int index}) {
    if (!column.isVisible) {
      return const SizedBox();
    }
    return Flexible(
      flex: column.size,
      child: ArDriveClickArea(
        child: Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: () {
              setState(() {
                if (_sortedColumn == index) {
                  _tableSort = _tableSort == TableSort.asc
                      ? TableSort.desc
                      : TableSort.asc;
                } else {
                  _sortedColumn = index;
                  _tableSort = TableSort.asc;
                }
              });

              _sortRows(index);

              // A new order is a new list, read from its start.
              selectPage(0);
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      column.title,
                      style: column.textStyle ??
                          ArDriveTypography.body.buttonNormalBold(),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (_sortedColumn == index)
                  _tableSort == TableSort.asc
                      ? ArDriveIcons.carretUp(
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeFgDefault)
                      : ArDriveIcons.carretDown(
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeFgDefault,
                        ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _masterMultiselectCheckBox() {
    final multiselectPage = getMultiSelectBox();

    final isMasterCheckBoxChecked = multiselectPage.page == _selectedPage &&
        multiselectPage.selectedItems.length == _currentPage.length;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: _isMultiSelecting ? checkboxSize + 14 : 0,
      child: ArDriveCheckBox(
        key: ValueKey(
          isMasterCheckBoxChecked.toString() +
              multiselectPage.page.toString() +
              multiselectPage.selectedItems.length.toString(),
        ),
        checked: isMasterCheckBoxChecked,
        isIndeterminate: multiselectPage.selectedItems.isNotEmpty &&
            multiselectPage.selectedItems.length != _currentPage.length,
        onChange: (value) {
          setState(() {
            if (value) {
              _selectAllItemsInPage();
            } else {
              multiselectPage.clear();
            }

            if (widget.onChangeMultiSelecting != null) {
              widget.onChangeMultiSelecting!(_isMultiSelecting);
            }
          });
        },
      ),
    );
  }

  Widget _multiSelectColumn(bool selectAll, {required T row, int? index}) {
    final multiselectPage = getMultiSelectBox();

    final isSelected = multiselectPage.selectedItems.any(
      (element) => element.index == row.index,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: _isMultiSelecting ? checkboxSize + 14 : 0,
      child: ArDriveCheckBox(
        key: ValueKey(
          index.toString() + isSelected.toString(),
        ),
        checked: isSelected,
        onChange: (value) {
          _onChangeItemCheck(
            row: row,
            index: index,
            value: value,
          );
        },
      ),
    );
  }

  void _onChangeItemCheck({
    T? row,
    int? index,
    required bool value,
  }) {
    setState(
      () {
        final wasMultiSelecting = _isMultiSelecting;
        if (row != null && index != null) {
          _selectMultiSelectItem(row, index, value);
        }

        if (_isMultiSelectingWithLongPress &&
            !value &&
            getMultiSelectBox().selectedItems.isEmpty) {
          _isMultiSelectingWithLongPress = false;
        }

        if (wasMultiSelecting != _isMultiSelecting &&
            widget.onChangeMultiSelecting != null) {
          widget.onChangeMultiSelecting!(_isMultiSelecting);
        }
      },
    );
  }

  /// The footer: rows per page, the pages, and which rows are on screen.
  ///
  /// Absent when every row fits on a page of the smallest size, where it
  /// would offer nothing to do.
  Widget _pageIndicator() {
    final total = _cachedRows.length;
    final options =
        {...widget.rowsPerPageOptions, _numberOfItemsPerPage}.toList()..sort();

    if (total <= options.first) {
      return const SizedBox.shrink();
    }

    final firstRow = _selectedPage * _numberOfItemsPerPage + 1;
    final lastRow = min(firstRow + _numberOfItemsPerPage - 1, total);

    return PaginationFooter(
      page: _selectedPage,
      pageCount: _pageCount,
      rangeText: (widget.pageRangeText ?? _defaultPageRangeText)(
        firstRow,
        lastRow,
        total,
      ),
      rowsPerPage: _numberOfItemsPerPage,
      rowsPerPageOptions: options,
      rowsPerPageText: widget.rowsPerPageText,
      previousPageText: widget.previousPageText,
      nextPageText: widget.nextPageText,
      pageText: widget.pageText ?? _defaultPageText,
      onPageSelected: selectPage,
      onRowsPerPageSelected: _onRowsPerPageChosen,
    );
  }

  Widget _buildRowSpacing(
    List<TableColumn> columns,
    List<Widget> buildRow,
    T row,
    int index,
  ) {
    final multiselect = getMultiSelectBox();

    return GestureDetector(
      onTapDown: (details) => _tapKind = details.kind,
      onTapCancel: () => _tapKind = null,
      onTap: () {
        if (_isMultiSelecting) {
          _tapKind = null;
          _onChangeItemCheck(
            value: !multiselect.selectedItems.any((r) => r.index == row.index),
            row: row,
            index: row.index,
          );
        } else {
          _onRowTapped(row);
        }
      },
      onLongPress: () {
        setState(() {
          _isMultiSelectingWithLongPress = !_isMultiSelectingWithLongPress;
        });

        if (widget.onChangeMultiSelecting != null) {
          widget.onChangeMultiSelecting!(_isMultiSelecting);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          _multiSelectColumn(false, index: index, row: row),
          Flexible(
            child: ArDriveCard(
              key: ValueKey(row),
              backgroundColor: (!_isMultiSelecting && _selectedItem == row) ||
                      multiselect.selectedItems.contains(row)
                  ? ArDriveTheme.of(context)
                      .themeData
                      .tableTheme
                      .selectedItemColor
                  : ArDriveTheme.of(context)
                      .themeData
                      .colors
                      .themeBorderDefault
                      .withOpacity(0.25),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 15, vertical: 0),
              content: Row(
                children: [
                  if (widget.leading != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 40,
                          maxHeight: 40,
                        ),
                        child: widget.leading!.call(row),
                      ),
                    ),
                  ...List.generate(
                    columns.length,
                    (index) {
                      if (!columns[index].isVisible) {
                        return const SizedBox();
                      }
                      return Flexible(
                        flex: columns[columns[index].index].size,
                        child: ArDriveClickArea(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: buildRow[columns[index].index],
                          ),
                        ),
                      );
                    },
                    growable: false,
                  ),
                  if (widget.trailing != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 20),
                      child: Container(
                        alignment: Alignment.center,
                        height: 44,
                        width: 100,
                        child: widget.trailing!.call(row),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void selectPage(int page) {
    final target = _clampPage(page);
    final changed = target != _selectedPage;

    setState(() {
      _selectedPage = target;
      _currentPage = _rowsOfPage(target);
    });

    if (!changed) {
      return;
    }

    // A new page starts at its top, as a new page of anything does. Now when
    // a click asked for it, so no frame shows the new rows at the old offset;
    // after the frame when the rows changed during a build.
    _afterBuild(() {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
    _afterBuild(() => widget.onChangePage?.call(target));
  }

  /// Brings [_scrollToRow] on screen, moving as little as it can.
  ///
  /// The list only builds the rows it shows, so a row further down has no
  /// context to scroll to yet: the list jumps to about where it will be, and
  /// looks again once that frame has built it.
  void _scrollRevealedRowIntoView([int attempt = 0]) {
    final row = _scrollToRow;
    if (!mounted || row == null || !_scrollController.hasClients) {
      return;
    }

    final rowContext = _scrollToRowKey.currentContext;
    if (rowContext != null) {
      _scrollToRow = null;
      Scrollable.ensureVisible(
        rowContext,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      Scrollable.ensureVisible(
        rowContext,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
      return;
    }

    final index = _currentPage.indexOf(row);
    if (index < 0 || attempt >= 3) {
      _scrollToRow = null;
      return;
    }

    final position = _scrollController.position;
    _scrollController.jumpTo(
      position.maxScrollExtent * index / max(1, _currentPage.length - 1),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollRevealedRowIntoView(attempt + 1),
    );
  }

  /// Runs [action] now, or after this frame when called during one: a
  /// listener told of a page change mid-build must not rebuild in it.
  void _afterBuild(VoidCallback action) {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) action();
      });
    } else {
      action();
    }
  }

  void goToNextPage() {
    selectPage(_selectedPage + 1);
  }

  void goToLastPage() {
    selectPage(_pageCount - 1);
  }

  void goToFirstPage() {
    selectPage(0);
  }

  void goToPreviousPage() {
    selectPage(_selectedPage - 1);
  }

  void _sortRows(int index) {
    final stopwatch = Stopwatch()..start();

    if (widget.sortRows != null) {
      _cachedRows = widget.sortRows!(_cachedRows, index, _tableSort!);
    } else if (widget.sort != null) {
      int sort(a, b) {
        if (_tableSort == TableSort.asc) {
          return widget.sort!.call(index)(a, b);
        } else {
          return widget.sort!.call(index)(b, a);
        }
      }

      _cachedRows.sort(sort);
    }

    selectPage(_selectedPage);

    stopwatch.stop();

    debugPrint(
      'TABLE SORT - Elapsed time: ${stopwatch.elapsedMilliseconds}ms',
    );
  }
}

String _defaultPageRangeText(int first, int last, int total) =>
    '$first-$last of $total';

String _defaultPageText(int page) => 'Page $page';

/// Which pages the pager shows, zero-based, with null for an ellipsis.
///
/// Always the first and last page, the current one and [siblings] either
/// side of it, with an ellipsis for each gap. A gap of one page shows that
/// page instead, so there are always the same number of slots: the buttons
/// do not move under the pointer as the reader pages through.
@visibleForTesting
List<int?> paginationSlots(int page, int pageCount, {int siblings = 1}) {
  final slots = 2 * siblings + 5;
  if (pageCount <= slots) {
    return List.generate(pageCount, (i) => i);
  }

  final last = pageCount - 1;
  final left = max(page - siblings, 1);
  final right = min(page + siblings, last - 1);
  final gapBefore = left > 2;
  final gapAfter = right < last - 2;
  final run = slots - 2;

  if (!gapBefore) {
    return [...List.generate(run, (i) => i), null, last];
  }
  if (!gapAfter) {
    return [0, null, ...List.generate(run, (i) => pageCount - run + i)];
  }
  return [0, null, for (var i = left; i <= right; i++) i, null, last];
}

/// The table's footer: rows per page on the left, the pages in the middle,
/// and which rows are on screen on the right.
///
/// It gives way as the table narrows, most useful last: first the pager
/// drops to fewer numbers, then the rows-per-page picker goes and the range
/// moves left, and at the narrowest the pager is its two arrows.
@visibleForTesting
class PaginationFooter extends StatelessWidget {
  const PaginationFooter({
    super.key,
    required this.page,
    required this.pageCount,
    required this.rangeText,
    required this.rowsPerPage,
    required this.rowsPerPageOptions,
    required this.rowsPerPageText,
    required this.previousPageText,
    required this.nextPageText,
    required this.pageText,
    required this.onPageSelected,
    required this.onRowsPerPageSelected,
  });

  final int page;
  final int pageCount;
  final String rangeText;
  final int rowsPerPage;
  final List<int> rowsPerPageOptions;
  final String rowsPerPageText;
  final String previousPageText;
  final String nextPageText;
  final String Function(int page) pageText;
  final void Function(int page) onPageSelected;
  final void Function(int rowsPerPage) onRowsPerPageSelected;

  /// Below this, the picker goes and the range moves left.
  static const double pickerMinWidth = 640;

  /// At or above this, the pager shows a page either side of the current.
  static const double fullPagerMinWidth = 720;

  /// Below this, the pager is its two arrows.
  static const double numbersMinWidth = 460;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final hasPages = pageCount > 1;

    Widget range(TextAlign align) => Text(
          rangeText,
          key: const ValueKey('pagination-range'),
          style: typography.paragraphNormal(color: colorTokens.textMid),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
        );

    Widget pager({required int siblings, bool numbers = true}) => _Pager(
          page: page,
          pageCount: pageCount,
          siblings: siblings,
          showNumbers: numbers,
          previousPageText: previousPageText,
          nextPageText: nextPageText,
          pageText: pageText,
          onPageSelected: onPageSelected,
        );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // In unscaled pixels, so large text reaches the compact layouts
          // sooner rather than overflowing the roomy ones.
          final width =
              constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1);

          if (width >= pickerMinWidth) {
            return Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _RowsPerPagePicker(
                      rowsPerPage: rowsPerPage,
                      options: rowsPerPageOptions,
                      label: rowsPerPageText,
                      onSelected: onRowsPerPageSelected,
                    ),
                  ),
                ),
                if (hasPages)
                  pager(siblings: width >= fullPagerMinWidth ? 1 : 0),
                Expanded(child: range(TextAlign.right)),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: range(TextAlign.left)),
              if (hasPages)
                pager(siblings: 0, numbers: width >= numbersMinWidth),
            ],
          );
        },
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.pageCount,
    required this.siblings,
    required this.showNumbers,
    required this.previousPageText,
    required this.nextPageText,
    required this.pageText,
    required this.onPageSelected,
  });

  final int page;
  final int pageCount;
  final int siblings;
  final bool showNumbers;
  final String previousPageText;
  final String nextPageText;
  final String Function(int page) pageText;
  final void Function(int page) onPageSelected;

  @override
  Widget build(BuildContext context) {
    final hasPrevious = page > 0;
    final hasNext = page < pageCount - 1;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PagerButton(
          key: const ValueKey('pagination-previous'),
          label: previousPageText,
          onPressed: hasPrevious ? () => onPageSelected(page - 1) : null,
          builder: (context, hovered) => _ArrowFace(
            icon: ArDriveIcons.carretLeft,
            enabled: hasPrevious,
            hovered: hovered,
          ),
        ),
        if (showNumbers)
          for (final slot
              in paginationSlots(page, pageCount, siblings: siblings))
            if (slot == null)
              const _Ellipsis()
            else
              _PagerButton(
                key: ValueKey('pagination-page-$slot'),
                label: pageText(slot + 1),
                selected: slot == page,
                onPressed: () => onPageSelected(slot),
                builder: (context, hovered) => _PageFace(
                  number: slot + 1,
                  selected: slot == page,
                  hovered: hovered,
                ),
              ),
        _PagerButton(
          key: const ValueKey('pagination-next'),
          label: nextPageText,
          onPressed: hasNext ? () => onPageSelected(page + 1) : null,
          builder: (context, hovered) => _ArrowFace(
            icon: ArDriveIcons.carretRight,
            enabled: hasNext,
            hovered: hovered,
          ),
        ),
      ],
    );
  }
}

/// One of the footer's controls, as a button rather than a tap target: it
/// is reached with Tab, pressed with Enter or Space, shows a ring while
/// focused, and tells a screen reader what it is.
///
/// Enter is bound here rather than left to the app's shortcuts because the
/// table around it already listens for Enter, to open the selected row, and
/// would hear it first.
class _PagerButton extends StatefulWidget {
  const _PagerButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.builder,
    this.selected = false,
    this.onKeyboardPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Pressed with Enter or Space rather than the pointer, when that should
  /// do more: a menu opened from the keyboard puts focus in itself.
  final VoidCallback? onKeyboardPressed;
  final bool selected;
  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<_PagerButton> createState() => _PagerButtonState();
}

class _PagerButtonState extends State<_PagerButton> {
  bool _hovered = false;
  bool _focused = false;

  static const _activators = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
  };

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.selected,
      label: widget.label,
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: enabled,
        shortcuts: _activators,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              (widget.onKeyboardPressed ?? widget.onPressed)?.call();
              return null;
            },
          ),
        },
        mouseCursor: enabled && !widget.selected
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                width: 2,
                color: _focused ? colorTokens.strokeHigh : Colors.transparent,
              ),
            ),
            child: widget.builder(
              context,
              _hovered && enabled && !widget.selected,
            ),
          ),
        ),
      ),
    );
  }
}

class _ArrowFace extends StatelessWidget {
  const _ArrowFace({
    required this.icon,
    required this.enabled,
    required this.hovered,
  });

  final ArDriveIcon Function({double? size, Color? color}) icon;
  final bool enabled;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final theme = ArDriveTheme.of(context).themeData;

    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: hovered ? theme.colorTokens.containerL1 : null,
        borderRadius: BorderRadius.circular(4),
      ),
      child: icon(
        color: enabled ? theme.colors.themeFgDefault : grey,
      ),
    );
  }
}

class _PageFace extends StatelessWidget {
  const _PageFace({
    required this.number,
    required this.selected,
    required this.hovered,
  });

  final int number;
  final bool selected;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final theme = ArDriveTheme.of(context).themeData;

    return Container(
      height: 32,
      constraints: const BoxConstraints(minWidth: 32),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(
          width: 2,
          color: selected
              ? theme.colors.themeFgDefault
              : theme.colors.themeGbMuted,
        ),
        borderRadius: BorderRadius.circular(4),
        color: selected
            ? theme.colors.themeFgDefault
            : hovered
                ? theme.colorTokens.containerL1
                : null,
      ),
      child: Text(
        '$number',
        style: ArDriveTypography.body.buttonNormalBold(
          color: selected
              ? theme.tableTheme.backgroundColor
              : theme.colors.themeFgDefault,
        ),
      ),
    );
  }
}

class _Ellipsis extends StatelessWidget {
  const _Ellipsis();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      // A page button's width - its face and the room around it for a focus
      // ring - so the pager is the same width whichever pages it shows.
      child: SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: ArDriveIcons.dots(
            size: 20,
            color: ArDriveTheme.of(context).themeData.colorTokens.textLow,
          ),
        ),
      ),
    );
  }
}

/// "Rows per page" and its menu.
///
/// A `MenuAnchor` rather than the app's `ArDriveDropdown`, which only hears
/// the pointer: here the trigger opens on Enter, the open menu puts focus on
/// the current size, the arrows move between sizes and Escape closes it.
class _RowsPerPagePicker extends StatefulWidget {
  const _RowsPerPagePicker({
    required this.rowsPerPage,
    required this.options,
    required this.label,
    required this.onSelected,
  });

  final int rowsPerPage;
  final List<int> options;
  final String label;
  final void Function(int rowsPerPage) onSelected;

  @override
  State<_RowsPerPagePicker> createState() => _RowsPerPagePickerState();
}

class _RowsPerPagePickerState extends State<_RowsPerPagePicker> {
  final _controller = MenuController();
  final _focusNodes = <int, FocusNode>{};

  /// Whether the menu was opened from the keyboard, and so takes focus. Not
  /// when opened with the pointer, where a focused item would show as a
  /// highlight nothing is hovering.
  bool _focusOnOpen = false;

  /// Escape, while the menu is open. The menu hears it itself only when
  /// focus is inside it, which a menu opened with the pointer does not take.
  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        _controller.isOpen) {
      _controller.close();
      return true;
    }
    return false;
  }

  void _toggle({required bool fromKeyboard}) {
    if (_controller.isOpen) {
      _controller.close();
      return;
    }
    _focusOnOpen = fromKeyboard;
    _controller.open();
  }

  FocusNode _nodeFor(int option) => _focusNodes.putIfAbsent(
        option,
        () => FocusNode(debugLabel: 'rows per page $option'),
      );

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ArDriveTheme.of(context).themeData;
    final typography = ArDriveTypographyNew.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: ExcludeSemantics(
            child: Text(
              widget.label,
              style: typography.paragraphNormal(
                color: theme.colorTokens.textMid,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 6),
        MenuAnchor(
          controller: _controller,
          // The menu lines up with the button's face, inside the room its
          // focus ring keeps.
          alignmentOffset: const Offset(4, 0),
          onClose: () => HardwareKeyboard.instance.removeHandler(_onKey),
          onOpen: () {
            HardwareKeyboard.instance.addHandler(_onKey);
            if (!_focusOnOpen) {
              return;
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _focusNodes[widget.rowsPerPage]?.requestFocus();
            });
          },
          style: MenuStyle(
            backgroundColor: MaterialStatePropertyAll(
              theme.dropdownTheme.backgroundColor,
            ),
            surfaceTintColor: const MaterialStatePropertyAll(
              Colors.transparent,
            ),
            padding: const MaterialStatePropertyAll(
              EdgeInsets.symmetric(vertical: 4),
            ),
            shape: MaterialStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
          menuChildren: [
            for (final option in widget.options)
              MenuItemButton(
                key: ValueKey('rows-per-page-$option'),
                focusNode: _nodeFor(option),
                onPressed: () => widget.onSelected(option),
                style: ButtonStyle(
                  minimumSize: const MaterialStatePropertyAll(Size(112, 40)),
                  overlayColor: MaterialStatePropertyAll(
                    theme.dropdownTheme.hoverColor,
                  ),
                ),
                leadingIcon: SizedBox(
                  width: 16,
                  child: option == widget.rowsPerPage
                      ? ArDriveIcons.checkmark(
                          size: 16,
                          color: theme.colors.themeFgDefault,
                        )
                      : null,
                ),
                child: Text(
                  '$option',
                  style: ArDriveTypography.body.buttonNormalBold(
                    color: theme.colors.themeFgDefault,
                  ),
                ),
              ),
          ],
          builder: (context, controller, child) => _PagerButton(
            key: const ValueKey('rows-per-page'),
            label: '${widget.label}: ${widget.rowsPerPage}',
            onPressed: () => _toggle(fromKeyboard: false),
            onKeyboardPressed: () => _toggle(fromKeyboard: true),
            builder: (context, hovered) => Container(
              height: 32,
              padding: const EdgeInsets.only(left: 10, right: 6),
              decoration: BoxDecoration(
                border: Border.all(width: 2, color: theme.colors.themeGbMuted),
                borderRadius: BorderRadius.circular(4),
                color: hovered ? theme.colorTokens.containerL1 : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${widget.rowsPerPage}',
                    style: ArDriveTypography.body.buttonNormalBold(
                      color: theme.colors.themeFgDefault,
                    ),
                  ),
                  const SizedBox(width: 2),
                  ArDriveIcons.carretDown(
                    size: 20,
                    color: theme.colors.themeFgDefault,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class MultiSelectBox<T> {
  final int page;
  final List<T> selectedItems;

  MultiSelectBox({
    required this.page,
    required this.selectedItems,
  });

  void add(T item) {
    selectedItems.add(item);
  }

  void addAll(List<T> items) {
    selectedItems.clear();
    selectedItems.addAll(items);
  }

  void remove(T item) {
    selectedItems.remove(item);
  }

  void clear() {
    selectedItems.clear();
  }
}

/// Paints a table row's hover state.
///
/// Rows here are clickable and did not look it: the table hands row building to
/// its caller, so nothing owned the hover and no caller drew one. Every table in
/// the app was affected, which is why this belongs here rather than in any one
/// of them.
class _HoverableRow extends StatefulWidget {
  const _HoverableRow({super.key, required this.child});

  final Widget child;

  @override
  State<_HoverableRow> createState() => _HoverableRowState();
}

class _HoverableRowState extends State<_HoverableRow> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: ColoredBox(
        color: _isHovering
            ? ArDriveTheme.of(context).themeData.colorTokens.containerL1
            : Colors.transparent,
        child: widget.child,
      ),
    );
  }
}

/// Tells the second click of a double-click from a click, without holding
/// the first one back.
///
/// `onDoubleTap` would do the telling, but a detector listening for a double
/// tap delays every single tap until the window closes, and a click that
/// takes a third of a second to select anything feels broken. So the first
/// click acts at once and arms this; a second click on the same thing inside
/// the platform's double-tap window completes it.
class ArDriveDoubleClick<T> {
  T? _armed;
  Timer? _timer;

  /// Whether a tap from [kind] opens a thing rather than selecting it.
  ///
  /// The file manager's rule, as Google Drive keeps it: a mouse click selects
  /// and a double-click opens, but a finger has no double-click and no hover
  /// to show what is chosen, so a tap opens. So does a tap with no pointer
  /// behind it at all - Enter or Space on something focused, or a screen
  /// reader's activate - because opening is what those ask for.
  static bool tapOpens(PointerDeviceKind? kind) =>
      kind == null ||
      kind == PointerDeviceKind.touch ||
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;

  /// Whether a click on [target] completes a double-click. Either way the
  /// window is spent.
  bool completes(T target) {
    final completes = _armed == target && (_timer?.isActive ?? false);
    reset();
    return completes;
  }

  /// A first click landed on [target].
  void arm(T target) {
    _timer?.cancel();
    _armed = target;
    _timer = Timer(kDoubleTapTimeout, reset);
  }

  void reset() {
    _timer?.cancel();
    _timer = null;
    _armed = null;
  }

  void dispose() => reset();
}
