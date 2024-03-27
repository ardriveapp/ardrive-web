import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_ui/src/constants/size_constants.dart';
import 'package:ardrive_ui/src/styles/colors/global_colors.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TableColumn {
  TableColumn(
    this.title,
    this.size, {
    required this.index,
    this.isVisible = true,
    this.canHide = true,
  });

  final String title;
  final int size;
  final bool isVisible;
  final int index;
  final bool canHide;
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
  final Function(int page)? onChangePage;
  final int pageItemsDivisorFactor;
  final int maxItemsPerPage;
  final String rowsPerPageText;
  final Function(List<MultiSelectBox<T>> selectedRows)? onSelectedRows;
  final Function(T row)? onRowTap;
  final Function(bool onChangeMultiSelecting)? onChangeMultiSelecting;
  final bool forceDisableMultiSelect;
  final bool lockMultiSelect;
  final T? selectedRow;
  final Function(TableColumn)? onChangeColumnVisibility;

  const ArDriveDataTable({
    super.key,
    required this.columns,
    required this.buildRow,
    required this.rows,
    this.leading,
    this.trailing,
    this.sort,
    this.pageItemsDivisorFactor = 25,
    this.onChangePage,
    this.maxItemsPerPage = 100,
    required this.rowsPerPageText,
    this.sortRows,
    this.onSelectedRows,
    this.onRowTap,
    this.onChangeMultiSelecting,
    this.forceDisableMultiSelect = false,
    this.lockMultiSelect = false,
    this.selectedRow,
    this.onChangeColumnVisibility,
  });

  @override
  State<ArDriveDataTable> createState() => _ArDriveDataTableState<T>();
}

enum TableSort { asc, desc }

abstract class IndexedItem with EquatableMixin {
  IndexedItem(this.index);

  final int index;
}

class _ArDriveDataTableState<T extends IndexedItem>
    extends State<ArDriveDataTable<T>> {
  late List<T> _cachedRows;
  late List<T> _currentPage;
  final List<MultiSelectBox<T>> _multiSelectBoxes = [];
  T? _selectedItem;
  List<TableColumn> _columns = [];

  final ScrollController _scrollController = ScrollController();

  late int _numberOfPages;
  late int _selectedPage;
  late int _pageItemsDivisorFactor;
  late int _numberOfItemsPerPage;
  int? _sortedColumn;
  bool _isMultiSelectingWithLongPress = false;

  TableSort? _tableSort;

  bool _isCtrlPressed = false;
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
    _pageItemsDivisorFactor = widget.pageItemsDivisorFactor;
    _numberOfItemsPerPage = _pageItemsDivisorFactor;
    _numberOfPages = _cachedRows.length ~/ _pageItemsDivisorFactor;

    if (_cachedRows.length % _pageItemsDivisorFactor != 0) {
      _numberOfPages++;
    }

    selectPage(0);

    RawKeyboard.instance.addListener(_handleKeyDownEvent);
    RawKeyboard.instance.addListener(_handleEscapeKey);
    RawKeyboard.instance.addListener(_handleSelectAllShortcut);

    _columns = widget.columns;
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

  void recalculatePageForNewNumberOfItemsPerPage(int newItemsPerPage) {
    setState(() {
      int newPage =
          ((_selectedPage) * _numberOfItemsPerPage) ~/ newItemsPerPage;

      _numberOfItemsPerPage = newItemsPerPage;

      // Clear the current selection because the items on the page have changed
      clearSelection();

      selectPage(newPage);
    });
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

  int _recalculateCurrentPage() {
    // calculate the new total number of items after removing the items
    int removedItemCount = _cachedRows.length - widget.rows.length;

    int newTotalItems = _cachedRows.length - removedItemCount;

    // calculate the new last page index
    int newLastPageIndex = (newTotalItems / _numberOfItemsPerPage).ceil() - 1;

    if (newLastPageIndex < 0) {
      newLastPageIndex = 0;
    }

    // if the current page is greater than the new last page index,
    // move the user to the last page
    if (_selectedPage > newLastPageIndex) {
      return newLastPageIndex;
    }

    return _selectedPage;
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

        selectPage(_recalculateCurrentPage());
      } else {
        if (_sortedColumn != null) {
          _sortRows(_sortedColumn!);
        }
      }
    }
  }

  void _handleEscapeKey(RawKeyEvent event) {
    if (mounted) {
      if (event.isKeyPressed(LogicalKeyboardKey.escape)) {
        setState(() {
          clearSelection();

          if (widget.onChangeMultiSelecting != null) {
            widget.onChangeMultiSelecting!(false);
          }
        });
      }
    }
  }

  /// Selects all items c=with ctrl / command + a
  void _handleSelectAllShortcut(RawKeyEvent event) {
    if (event.isKeyPressed(LogicalKeyboardKey.keyA) && _isCtrlPressed) {
      _selectAllItemsInPage();
    }
  }

  void _handleKeyDownEvent(RawKeyEvent event) {
    if (mounted) {
      if (widget.lockMultiSelect) {
        return;
      }

      setState(() {
        if (event.isKeyPressed(LogicalKeyboardKey.metaLeft) ||
            event.isKeyPressed(LogicalKeyboardKey.controlLeft)) {
          _isCtrlPressed = true;
        } else {
          _isCtrlPressed = false;
        }

        if (widget.onChangeMultiSelecting != null) {
          widget.onChangeMultiSelecting!(_isMultiSelecting);
        }
      });
    }
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
      } else if (RawKeyboard.instance.keysPressed
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

  int _getNumberOfPages() {
    _numberOfPages = _cachedRows.length ~/ _numberOfItemsPerPage;

    if (_cachedRows.length % _numberOfItemsPerPage != 0) {
      _numberOfPages = _numberOfPages + 1;
    }

    return _numberOfPages;
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

    return ArDriveCard(
      backgroundColor:
          ArDriveTheme.of(context).themeData.tableTheme.backgroundColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      key: widget.key,
      content: Column(
        children: [
          const SizedBox(
            height: 28,
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
                                  bottom: (i == _columns.length - 1) ? 16 : 8),
                              child: ArDriveCheckBox(
                                isDisabled: !_columns[i].canHide,
                                title: _columns[i].title,
                                checked: _columns[i].isVisible,
                                titleStyle:
                                    ArDriveTypography.body.buttonLargeBold(),
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
          const SizedBox(
            height: 25,
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
                      child: Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: _buildRowSpacing(
                          _columns,
                          widget.buildRow(_currentPage[index]).row,
                          _currentPage[index],
                          index,
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
    );
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
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      column.title,
                      style: ArDriveTypography.body.buttonNormalBold(),
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

  Widget _pageIndicator() {
    return Padding(
      padding: const EdgeInsets.all(36.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.max,
            children: [
              ArDriveClickArea(
                showCursor: _selectedPage > 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    if (_selectedPage > 0) {
                      goToPreviousPage();
                    }
                  },
                  child: SizedBox(
                    height: 32,
                    width: 32,
                    child: Center(
                      child: ArDriveIcons.carretLeft(
                        color: _selectedPage > 0
                            ? ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeFgDefault
                            : grey,
                      ),
                    ),
                  ),
                ),
              ),
              if (_getPagesToShow().first > 1) ...[
                _pageNumber(0),
                if (_getPagesToShow().first > 2)
                  Row(
                    children: [
                      ArDriveIcons.dots(
                        size: 24,
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgDefault,
                      ),
                    ],
                  ),
              ],
              ..._getPagesIndicators(),
              if (_getPagesToShow().last < _getNumberOfPages() &&
                  _getPagesToShow().last < _getNumberOfPages() - 1)
                GestureDetector(
                  onTap: () {
                    goToLastPage();
                  },
                  child: Row(
                    children: [
                      ArDriveIcons.dots(
                        size: 24,
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgDefault,
                      ),
                      _pageNumber(_getNumberOfPages() - 1),
                    ],
                  ),
                ),
              ArDriveClickArea(
                showCursor: _selectedPage + 1 < _getNumberOfPages(),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    if (_selectedPage + 1 < _getNumberOfPages()) {
                      goToNextPage();
                    }
                  },
                  child: SizedBox(
                    height: 32,
                    width: 32,
                    child: Center(
                      child: ArDriveIcons.carretRight(
                        color: _selectedPage + 1 < _getNumberOfPages()
                            ? ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeFgDefault
                            : grey,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  List<int> _getPagesToShow() {
    late int visiblePages;
    final int numberOfPages = _getNumberOfPages();

    if (numberOfPages < 5) {
      visiblePages = numberOfPages;
    } else {
      visiblePages = 5;
    }

    final int half = visiblePages ~/ 2;
    final int start = _selectedPage + 1 - half;
    final int end = _selectedPage + 1 + half;

    if (start <= 0) {
      return List.generate(
        visiblePages,
        (index) => index + 1,
        growable: false,
      );
    }

    if (end >= numberOfPages) {
      return List.generate(
        visiblePages,
        (index) => numberOfPages - visiblePages + index + 1,
        growable: false,
      );
    }

    return List.generate(
      visiblePages,
      (index) => start + index,
      growable: false,
    );
  }

  /// The pages are counted starting from 0, so, to show correctly add + 1
  ///
  List<Widget> _getPagesIndicators() {
    return _getPagesToShow().map((page) {
      return _pageNumber(page - 1);
    }).toList();
  }

  Widget _pageNumber(int page) {
    return _PageNumber(
      page: page,
      isSelected: _selectedPage == page,
      onPressed: () {
        selectPage(page);
      },
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
      onTap: () {
        if (_isMultiSelecting) {
          _onChangeItemCheck(
            value: !multiselect.selectedItems.any((r) => r.index == row.index),
            row: row,
            index: row.index,
          );
        } else {
          setState(() {
            _selectedItem = row;
          });

          widget.onRowTap?.call(row);
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
    setState(() {
      _selectedPage = page;

      int maxIndex = _cachedRows.length < (page + 1) * _numberOfItemsPerPage
          ? _cachedRows.length
          : (page + 1) * _numberOfItemsPerPage;

      int minIndex = (_selectedPage * _numberOfItemsPerPage);

      _currentPage = _cachedRows.sublist(minIndex, maxIndex);
    });
  }

  void goToNextPage() {
    selectPage(_selectedPage + 1);
  }

  void goToLastPage() {
    selectPage(_numberOfPages - 1);
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

class PaginationSelect extends StatefulWidget {
  const PaginationSelect({
    super.key,
    required this.maxOption,
    required this.divisorFactor,
    required this.onSelect,
    required this.maxNumber,
    this.currentNumber,
  });

  final int maxOption;
  final int maxNumber;
  final int divisorFactor;
  final Function(int) onSelect;
  final int? currentNumber;

  @override
  State<PaginationSelect> createState() => _PaginationSelectState();
}

class _PaginationSelectState extends State<PaginationSelect> {
  late int currentNumber;

  @override
  void initState() {
    super.initState();
    if (widget.currentNumber != null) {
      currentNumber = widget.currentNumber!;
    } else {
      if (widget.maxNumber < widget.divisorFactor) {
        currentNumber = widget.maxNumber;
      } else {
        currentNumber = widget.divisorFactor;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ArDriveDropdown(
      anchor: const Aligned(
        follower: Alignment.bottomLeft,
        target: Alignment.bottomRight,
      ),
      items: [
        for (int i = widget.divisorFactor;
            i <= widget.maxOption && i <= widget.maxNumber;
            i += widget.divisorFactor)
          ArDriveDropdownItem(
            onClick: () {
              setState(() {
                currentNumber = i;
              });
              widget.onSelect(currentNumber);
            },
            content: Text(
              i.toString(),
              style: ArDriveTypography.body.buttonLargeBold(),
            ),
          ),
      ],
      child: ArDriveClickArea(
        child: _PageNumber(
          page: currentNumber - 1,
          isSelected: false,
        ),
      ),
    );
  }
}

class _PageNumber extends StatelessWidget {
  const _PageNumber({
    this.onPressed,
    required this.page,
    required this.isSelected,
  });

  final int page;
  final bool isSelected;
  final Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    return ArDriveClickArea(
      child: GestureDetector(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
                decoration: BoxDecoration(
                  border: Border.all(
                    width: 2,
                    color: isSelected
                        ? ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgDefault
                        : ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeGbMuted,
                  ),
                  borderRadius: BorderRadius.circular(4),
                  color: isSelected
                      ? ArDriveTheme.of(context).themeData.colors.themeFgDefault
                      : null,
                ),
                child: Text(
                  _showSemanticPageNumber(page),
                  style: ArDriveTypography.body.buttonNormalBold(
                    color: isSelected
                        ? ArDriveTheme.of(context)
                            .themeData
                            .tableTheme
                            .backgroundColor
                        : ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgDefault,
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

String _showSemanticPageNumber(int page) {
  return (page + 1).toString();
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
