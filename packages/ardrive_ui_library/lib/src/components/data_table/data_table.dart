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
    this.pageItemsDivisorFactor,
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
  final int? pageItemsDivisorFactor;
  final int maxItemsPerPage;

  @override
  State<ArDriveTable> createState() => _ArDriveTableState<T>();
}

enum TableSort { asc, desc }

class _ArDriveTableState<T> extends State<ArDriveTable<T>> {
  late List<T> rows;
  late List<T> sortedRows;
  late List<T> currentPage;

  int? numberOfPages;
  int? selectedPage;
  int? pageItemsDivisorFactor;
  int? numberOfItemsPerPage;
  int? sortedColumn;

  TableSort? _tableSort;

  @override
  void initState() {
    super.initState();
    rows = widget.rows;
    sortedRows = List.from(rows);
    if (widget.pageItemsDivisorFactor != null) {
      pageItemsDivisorFactor = widget.pageItemsDivisorFactor;
      numberOfItemsPerPage = pageItemsDivisorFactor;
      numberOfPages = rows.length ~/ pageItemsDivisorFactor!;
      if (rows.length % pageItemsDivisorFactor! != 0) {
        numberOfPages = numberOfPages! + 1;
      }
      selectedPage = 0;
      selectPage(0);
    } else {
      currentPage = widget.rows;
    }
  }

  int getNumberOfPages() {
    numberOfPages = rows.length ~/ numberOfItemsPerPage!;
    if (rows.length % numberOfItemsPerPage! != 0) {
      numberOfPages = numberOfPages! + 1;
    }
    return numberOfPages!;
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

                    selectPage(selectedPage!);
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
      content: SingleChildScrollView(
        child: Column(
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
            for (var row in currentPage)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: _buildRowSpacing(
                  widget.columns,
                  widget.buildRow(row).row,
                  row,
                ),
              ),
            if (widget.pageItemsDivisorFactor != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Rows per page ',
                          style: ArDriveTypography.body.bodyBold(),
                        ),
                        PaginationSelect(
                          currentNumber: numberOfItemsPerPage,
                          divisorFactor: pageItemsDivisorFactor!,
                          maxOption: widget.maxItemsPerPage,
                          maxNumber: widget.rows.length,
                          onSelect: (n) {
                            setState(() {
                              int newPage =
                                  ((selectedPage!) * numberOfItemsPerPage!) ~/
                                      n;

                              numberOfItemsPerPage = n;

                              selectPage(newPage);
                            });
                          },
                        ),
                      ],
                    ),
                    Text(
                      '${_getMinIndexInView()}-${_getMaxIndexInView()} of ${rows.length}',
                      style: ArDriveTypography.body.bodyBold(),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (getNumberOfPages() > 5 && selectedPage! >= 3)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0, right: 8),
                            child: GestureDetector(
                              onTap: () {
                                if (selectedPage! > 0) {
                                  goToFirstPage();
                                }
                              },
                              child: Icon(
                                Icons.keyboard_double_arrow_left,
                                color: selectedPage! > 0 ? null : grey,
                                size: 14,
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0, right: 12),
                          child: GestureDetector(
                            onTap: () {
                              if (selectedPage! > 0) {
                                goToThePreviousPage();
                              }
                            },
                            child: Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: selectedPage! > 0 ? null : grey,
                              size: 12,
                            ),
                          ),
                        ),
                        if (getNumberOfPages() > 5 && selectedPage! >= 3)
                          Text(
                            '1 ...',
                            style: ArDriveTypography.body.inputLargeBold(
                              color: selectedPage == 1 ? null : grey,
                            ),
                          ),
                        ..._getPagesIndicators2(),
                        if (getNumberOfPages() > 5 &&
                            selectedPage! < numberOfPages! - 3)
                          GestureDetector(
                            onTap: () {
                              selectPage(getNumberOfPages() - 1);
                            },
                            child: Text(
                              '... ${getNumberOfPages()}',
                              style: ArDriveTypography.body.inputLargeBold(
                                color: selectedPage == getNumberOfPages() - 1
                                    ? null
                                    : grey,
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0, left: 8),
                          child: GestureDetector(
                            onTap: () {
                              if (selectedPage! + 1 < getNumberOfPages()) {
                                goToNextPage();
                              }
                            },
                            child: Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: selectedPage! + 1 < getNumberOfPages()
                                  ? null
                                  : grey,
                              size: 14,
                            ),
                          ),
                        ),
                        if (getNumberOfPages() > 6)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0, left: 12),
                            child: GestureDetector(
                              onTap: () {
                                if (selectedPage! + 1 < getNumberOfPages()) {
                                  goToLastPage();
                                }
                              },
                              child: Icon(
                                Icons.keyboard_double_arrow_right,
                                color: selectedPage! + 1 < getNumberOfPages()
                                    ? null
                                    : grey,
                                size: 14,
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
      ),
    );
  }

  List<Widget> _getPagesIndicators2() {
    if (numberOfPages! < 6) {
      return List.generate(numberOfPages!, (index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: GestureDetector(
            onTap: () {
              selectPage(index);
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  (index + 1).toString(),
                  style: ArDriveTypography.body.inputLargeBold(
                    color: selectedPage! == index ? null : grey,
                  ),
                ),
                if (index < numberOfPages! - 1)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      '|',
                      style: ArDriveTypography.body.buttonLargeRegular(
                        color: grey,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      });
    } else {
      if (selectedPage! + 1 == 1) {
        return List.generate(5, (index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: GestureDetector(
              onTap: () {
                selectPage(index);
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    (index + 1).toString(),
                    style: ArDriveTypography.body.inputLargeBold(
                      color: selectedPage! == index ? null : grey,
                    ),
                  ),
                  if (index < numberOfPages! - 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(
                        '|',
                        style: ArDriveTypography.body.buttonLargeRegular(
                          color: grey,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        });
      } else if (selectedPage! == 1) {
        List<Widget> items = [];
        for (int i = selectedPage!; i <= selectedPage! + 4; i++) {
          items.add(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: GestureDetector(
              onTap: () {
                selectPage(i);
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    (i).toString(),
                    style: ArDriveTypography.body.inputLargeBold(
                      color: selectedPage! + 1 == i ? null : grey,
                    ),
                  ),
                  if (i < numberOfPages! - 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(
                        '|',
                        style: ArDriveTypography.body.buttonLargeRegular(
                          color: grey,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ));
        }
        return items;
      } else if (selectedPage! >= numberOfPages! - 2) {
        List<Widget> items = [];

        for (int i = numberOfPages! - 1; i >= selectedPage! - 4; i--) {
          items.add(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: GestureDetector(
              onTap: () {
                selectPage(i);
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    (i + 1).toString(),
                    style: ArDriveTypography.body.inputLargeBold(
                      color: selectedPage! == i ? null : grey,
                    ),
                  ),
                  if (i < numberOfPages!)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(
                        '|',
                        style: ArDriveTypography.body.buttonLargeRegular(
                          color: grey,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ));
        }
        return items.reversed.toList();
      } else {
        List<Widget> items = [];

        for (int i = selectedPage! - 2; i <= selectedPage! + 2; i++) {
          items.add(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: GestureDetector(
              onTap: () {
                selectPage(i);
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    (i + 1).toString(),
                    style: ArDriveTypography.body.inputLargeBold(
                      color: selectedPage! == i ? null : grey,
                    ),
                  ),
                  if (i < numberOfPages! - 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(
                        '|',
                        style: ArDriveTypography.body.buttonLargeRegular(
                          color: grey,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ));
        }
        return items;
      }
    }
  }

  Widget _buildRowSpacing(
      List<TableColumn> columns, List<Widget> buildRow, T row) {
    return ArDriveCard(
      backgroundColor: ArDriveTheme.of(context).themeData.tableTheme.cellColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      content: Row(
        children: [
          if (widget.leading != null)
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: SizedBox(
                  height: 40, width: 40, child: widget.leading!.call(row)),
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

  selectPage(int page) {
    setState(() {
      selectedPage = page;
      int maxIndex = rows.length - 1 < (page + 1) * numberOfItemsPerPage!
          ? rows.length - 1
          : (page + 1) * numberOfItemsPerPage!;

      int minIndex = (selectedPage! * numberOfItemsPerPage!);

      currentPage = sortedRows.sublist(minIndex, maxIndex);
    });
  }

  void goToNextPage() {
    selectPage(selectedPage! + 1);
  }

  void goToLastPage() {
    selectPage(numberOfPages! - 1);
  }

  void goToFirstPage() {
    selectPage(0);
  }

  void goToThePreviousPage() {
    selectPage(selectedPage! - 1);
  }

  int _getMinIndexInView() {
    return (selectedPage! * numberOfItemsPerPage!) + 1;
  }

  int _getMaxIndexInView() {
    return (rows.length - 1 < (selectedPage! + 1) * numberOfItemsPerPage!
        ? rows.length
        : (selectedPage! + 1) * numberOfItemsPerPage!);
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
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            width: 1,
            color: ArDriveTheme.of(context).themeData.colors.themeFgSubtle,
          ),
        ),
        padding: const EdgeInsets.symmetric(
          vertical: 6,
          horizontal: 12,
        ),
        child: Row(
          children: [
            Text(
              '$currentNumber',
              style: ArDriveTypography.body.bodyBold(),
            ),
            const SizedBox(
              width: 8,
            ),
            const Icon(Icons.arrow_drop_down)
          ],
        ),
      ),
    );
  }
}
