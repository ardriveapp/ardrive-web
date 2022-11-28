import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:ardrive_ui_library/src/components/listtile.dart';
import 'package:ardrive_ui_library/src/styles/colors/global_colors.dart';
import 'package:flutter/material.dart';
import 'package:number_paginator/number_paginator.dart';

class ArDriveDataTable extends StatefulWidget {
  final List<List<Widget>> rows;
  final List<Widget> columns;

  const ArDriveDataTable({
    super.key,
    required this.rows,
    required this.columns,
  });

  @override
  State<ArDriveDataTable> createState() => _ArDriveDataTableState();
}

class _ArDriveDataTableState extends State<ArDriveDataTable> {
  List<int> selectedIndexes = [];
  bool multiSelect = false;
  int pageIndex = 0;

  List<List<Widget>> getPage(int index) {
    return widget.rows.sublist(pageIndex * 25, pageIndex + 25);
  }

  int numberOfPages() => widget.rows.length ~/ 25;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
      child: Card(
        margin: const EdgeInsets.all(16),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        color: ArDriveTheme.of(context).themeData.colors.themeBgSurface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              height: 84,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: widget.columns.first,
                    ),
                  ),
                  ...widget.columns
                      .sublist(1)
                      .map((column) => Flexible(child: column)),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: 24,
                padding: const EdgeInsets.all(8),
                itemBuilder: (context, index) {
                  return ArDriveListTile(
                    selected: selectedIndexes.contains(index) ? true : false,
                    onTap: () {
                      setState(() {
                        if (selectedIndexes.contains(index)) {
                          selectedIndexes.remove(index);
                        } else {
                          if (multiSelect) {
                            selectedIndexes.add(index);
                          } else {
                            selectedIndexes = [index];
                          }
                        }
                      });
                    },
                    title: SizedBox(
                      height: 80,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            flex: 2,
                            child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 28),
                                child: getPage(pageIndex)[index].first),
                          ),
                          ...getPage(pageIndex)[index]
                              .sublist(1)
                              .map((cell) => Flexible(child: cell)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            NumberPaginator(
              numberPages: numberOfPages(),
              onPageChange: (int index) {
                setState(() {
                  pageIndex = index;
                });
              },
            )
          ],
        ),
      ),
    );
  }
}

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
    this.rowsPerPage,
    this.onChangePage,
  });

  final List<TableColumn> columns;
  final List<T> rows;
  final TableRowWidget Function(T row) buildRow;
  final Widget Function(T row)? leading;
  final Widget Function(T row)? trailing;
  final int Function(T a, T b) Function(int columnIndex)? sort;
  final Function(int page)? onChangePage;
  final int? rowsPerPage;

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

  int? sortedColumn;

  TableSort? _tableSort;

  @override
  void initState() {
    super.initState();
    rows = widget.rows;
    sortedRows = List.from(rows);
    if (widget.rowsPerPage != null) {
      print(rows.length);
      numberOfPages = rows.length ~/ widget.rowsPerPage!;
      if (rows.length % widget.rowsPerPage! != 0) {
        numberOfPages = numberOfPages! + 1;
      }
      selectedPage = 0;
      print(numberOfPages);

      currentPage = widget.rows.sublist(0, widget.rowsPerPage!);
    }
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
        child: Padding(
          padding: EdgeInsets.only(bottom: 20),
          child: Column(
            children: [
              const SizedBox(
                height: 28,
              ),
              for (var row in currentPage)
                Padding(
                  padding: getPadding(),
                  child: Row(
                    children: [...columns],
                  ),
                ),
              if (widget.rowsPerPage != null)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Text(
                        'Rows per page: ${widget.rowsPerPage}',
                        style: ArDriveTypography.body.bodyBold(),
                      ),
                      Text(
                        '${_getMinIndexInView()}-${_getMaxIndexInView()} of ${rows.length}',
                        style: ArDriveTypography.body.bodyBold(),
                      ),
                      Row(
                        children: [
                          ...List.generate(
                            numberOfPages!,
                            (index) => Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4.0),
                              child: GestureDetector(
                                onTap: () {
                                  print('current page ${index + 1}');
                                  selectPage(index);
                                },
                                child: Text(
                                  (index + 1).toString(),
                                  style: ArDriveTypography.body.inputLargeBold(
                                      color:
                                          selectedPage == index ? null : grey),
                                ),
                              ),
                            ),
                          )
                        ],
                      )
                    ],
                  ),
                )
            ],
          ),
        ),
      ),
    );
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
      int maxIndex = rows.length - 1 < (page + 1) * widget.rowsPerPage!
          ? rows.length
          : (page + 1) * widget.rowsPerPage!;

      int minIndex = (selectedPage! * widget.rowsPerPage!);

      currentPage = sortedRows.sublist(minIndex, maxIndex);
    });
  }

  _getMinIndexInView() {
    return (selectedPage! * widget.rowsPerPage!) + 1;
  }

  _getMaxIndexInView() {
    return (rows.length - 1 < (selectedPage! + 1) * widget.rowsPerPage!
        ? rows.length
        : (selectedPage! + 1) * widget.rowsPerPage!);
  }
}
