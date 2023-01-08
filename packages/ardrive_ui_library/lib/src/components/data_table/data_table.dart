import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:ardrive_ui_library/src/styles/colors/global_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_portal/flutter_portal.dart';

class TableColumn {
  TableColumn(this.title, this.size);

  final String title;
  final int size;
}

class TableRowWidget {
  TableRowWidget(this.row);

  final List<Widget> row;
}

class TableRow {}

class ArDriveTable<T> extends StatefulWidget {
  const ArDriveTable({
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
  });

  final List<TableColumn> columns;
  final List<T> rows;
  final TableRowWidget Function(T row) buildRow;
  final Widget Function(T row)? leading;
  final Widget Function(T row)? trailing;
  final int Function(T a, T b) Function(int columnIndex)? sort;
  final Function(int page)? onChangePage;
  final int pageItemsDivisorFactor;
  final int maxItemsPerPage;

  @override
  State<ArDriveTable> createState() => _ArDriveTableState<T>();
}

enum TableSort { asc, desc }

class _ArDriveTableState<T> extends State<ArDriveTable<T>> {
  late List<T> rows;
  late List<T> sortedRows;
  late List<T> currentPage;

  late int numberOfPages;
  late int selectedPage;
  late int pageItemsDivisorFactor;
  late int numberOfItemsPerPage;
  int? sortedColumn;

  TableSort? _tableSort;

  @override
  void initState() {
    super.initState();
    rows = widget.rows;
    sortedRows = List.from(rows);
    pageItemsDivisorFactor = widget.pageItemsDivisorFactor;
    numberOfItemsPerPage = pageItemsDivisorFactor;
    numberOfPages = rows.length ~/ pageItemsDivisorFactor;
    if (rows.length % pageItemsDivisorFactor != 0) {
      numberOfPages = numberOfPages + 1;
    }
    selectedPage = 0;
    selectPage(0);
  }

  int getNumberOfPages() {
    numberOfPages = rows.length ~/ numberOfItemsPerPage;
    if (rows.length % numberOfItemsPerPage != 0) {
      numberOfPages = numberOfPages + 1;
    }
    return numberOfPages;
  }

  @override
  Widget build(BuildContext context) {
    final columns = List.generate(
      widget.columns.length,
      (index) {
        return Flexible(
          flex: widget.columns[index].size,
          child: Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () {
                if (widget.sort != null) {
                  setState(() {
                    if (sortedColumn == index) {
                      if (_tableSort == TableSort.asc) {
                        _tableSort = TableSort.desc;
                      } else {
                        _tableSort = TableSort.asc;
                      }
                    } else {
                      _tableSort = TableSort.asc;
                    }
                    int sort(T a, T b) {
                      if (_tableSort == TableSort.desc) {
                        return widget.sort!.call(index)(a, b);
                      } else {
                        return widget.sort!.call(index)(b, a);
                      }
                    }

                    sortedColumn = index;

                    sortedRows.sort(sort);

                    selectPage(selectedPage);
                  });
                }
              },
              child: Row(children: [
                Text(
                  widget.columns[index].title,
                  style: ArDriveTypography.body.buttonNormalBold(),
                ),
                if (sortedColumn == index)
                  Icon(
                    _tableSort == TableSort.asc
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                    size: 14,
                  )
              ]),
            ),
          ),
        );
      },
    );
    EdgeInsets getPadding() {
      double rightPadding = 0;
      double leftPadding = 0;

      if (widget.leading != null) {
        leftPadding = 80;
      } else {
        leftPadding = 20;
      }
      if (widget.trailing != null) {
        rightPadding = 80;
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
          Padding(
            padding: getPadding(),
            child: Row(
              children: [...columns],
            ),
          ),
          const SizedBox(
            height: 25,
          ),
          Expanded(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height,
              ),
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (var row in currentPage) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: _buildRowSpacing(
                      widget.columns,
                      widget.buildRow(row).row,
                      row,
                    ),
                  ),
                ],
              ])),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Row(
                  children: [
                    Text(
                      'Rows per page ',
                      style: ArDriveTypography.body.buttonNormalBold(),
                    ),
                    PaginationSelect(
                      currentNumber: numberOfItemsPerPage,
                      divisorFactor: pageItemsDivisorFactor,
                      maxOption: widget.maxItemsPerPage,
                      maxNumber: widget.rows.length,
                      onSelect: (n) {
                        setState(() {
                          int newPage =
                              ((selectedPage) * numberOfItemsPerPage) ~/ n;

                          numberOfItemsPerPage = n;

                          selectPage(newPage);
                        });
                      },
                    ),
                  ],
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0, right: 0),
                      child: GestureDetector(
                        onTap: () {
                          if (selectedPage > 0) {
                            goToThePreviousPage();
                          }
                        },
                        child: ArDriveIcons.chevronLeft(
                          size: 28,
                          color: selectedPage > 0
                              ? ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeFgDefault
                              : grey,
                        ),
                      ),
                    ),
                    if (getNumberOfPages() > 5 && selectedPage >= 3)
                      GestureDetector(
                        onTap: () {
                          goToFirstPage();
                        },
                        child: Row(
                          children: [
                            _pageNumber(0),
                            ArDriveIcons.dots(
                              size: 24,
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeFgDefault,
                            ),
                          ],
                        ),
                      ),
                    ..._getPagesIndicators(),
                    if (getNumberOfPages() > 5 &&
                        selectedPage < numberOfPages - 3)
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
                            _pageNumber(getNumberOfPages() - 1),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0, left: 8),
                      child: GestureDetector(
                        onTap: () {
                          if (selectedPage + 1 < getNumberOfPages()) {
                            goToNextPage();
                          }
                        },
                        child: ArDriveIcons.chevronRight(
                          color: selectedPage + 1 < getNumberOfPages()
                              ? ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeFgDefault
                              : grey,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  List<Widget> _getPagesIndicators() {
    if (numberOfPages < 6) {
      return List.generate(numberOfPages, (index) {
        return _pageNumber(index);
      });
    } else {
      List<Widget> items = [];

      /// 1, 2, 3, 4, 5, 6 ... max
      if (selectedPage <= 1) {
        return List.generate(5, (index) {
          return _pageNumber(index);
        });
      } else if (selectedPage >= numberOfPages - 2) {
        /// 1 ... x1, x2, x3, x4, max
        for (int i = numberOfPages - 1; i >= selectedPage - 4; i--) {
          items.add(_pageNumber(i));
        }

        return items.reversed.toList();
      } else {
        /// 1...x1, x2, selectedPage, x3, x4 ... max
        for (int i = selectedPage - 2; i <= selectedPage + 2; i++) {
          items.add(_pageNumber(i));
        }

        return items;
      }
    }
  }

  int showSemanticPage() {
    return selectedPage + 1;
  }

  /// The pages are counted starting from 0, so, to show correctly add + 1
  ///
  Widget _pageNumber(int page) {
    return _PageNumber(
      page: page,
      isSelected: selectedPage == page,
      onPressed: () {
        selectPage(page);
      },
    );
  }

  Widget _buildRowSpacing(
      List<TableColumn> columns, List<Widget> buildRow, T row) {
    return ArDriveCard(
      backgroundColor:
          ArDriveTheme.of(context).themeData.colors.themeBorderDefault,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      content: Row(
        children: [
          if (widget.leading != null)
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: SizedBox(
                height: 40,
                width: 40,
                child: widget.leading!.call(row),
              ),
            ),
          ...List.generate(columns.length, (index) {
            return Flexible(
              flex: columns[index].size,
              child: Align(
                alignment: Alignment.centerLeft,
                child: buildRow[index],
              ),
            );
          }),
          if (widget.trailing != null)
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: SizedBox(
                height: 40,
                width: 40,
                child: widget.trailing!.call(row),
              ),
            ),
        ],
      ),
    );
  }

  void selectPage(int page) {
    setState(() {
      selectedPage = page;
      int maxIndex = rows.length - 1 < (page + 1) * numberOfItemsPerPage
          ? rows.length - 1
          : (page + 1) * numberOfItemsPerPage;

      int minIndex = (selectedPage * numberOfItemsPerPage);

      currentPage = sortedRows.sublist(minIndex, maxIndex);
    });
  }

  void goToNextPage() {
    selectPage(selectedPage + 1);
  }

  void goToLastPage() {
    selectPage(numberOfPages - 1);
  }

  void goToFirstPage() {
    selectPage(0);
  }

  void goToThePreviousPage() {
    selectPage(selectedPage - 1);
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
      width: 100,
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
      child: _PageNumber(
        page: currentNumber - 1,
        isSelected: false,
      ),
    );
  }
}

class _PageNumber extends StatelessWidget {
  const _PageNumber({
    this.onPressed,
    required this.page,
    required this.isSelected,
    super.key,
  });

  final int page;
  final bool isSelected;
  final Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
                      ? ArDriveTheme.of(context).themeData.colors.themeFgDefault
                      : ArDriveTheme.of(context).themeData.colors.themeGbMuted,
                ),
                borderRadius: BorderRadius.circular(4),
                color: isSelected
                    ? ArDriveTheme.of(context).themeData.colors.themeFgDefault
                    : null,
              ),
              child: Text(
                (page + 1).toString(),
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
    );
  }
}
