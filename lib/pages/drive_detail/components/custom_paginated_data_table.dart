import 'dart:math' as math;

import 'package:ardrive/theme/theme.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

class CustomPaginatedDataTable extends StatefulWidget {
  /// Creates a widget describing a paginated [DataTable] on a [Card].
  ///
  /// The [header] should give the card's header, typically a [Text] widget.
  ///
  /// The [columns] argument must be a list of as many [DataColumn] objects as
  /// the table is to have columns, ignoring the leading checkbox column if any.
  /// The [columns] argument must have a length greater than zero and cannot be
  /// null.
  ///
  /// If the table is sorted, the column that provides the current primary key
  /// should be specified by index in [sortColumnIndex], 0 meaning the first
  /// column in [columns], 1 being the next one, and so forth.
  ///
  /// The actual sort order can be specified using [sortAscending]; if the sort
  /// order is ascending, this should be true (the default), otherwise it should
  /// be false.
  ///
  /// The [source] must not be null. The [source] should be a long-lived
  /// [DataTableSource]. The same source should be provided each time a
  /// particular [CustomPaginatedDataTable] widget is created; avoid creating a new
  /// [DataTableSource] with each new instance of the [CustomPaginatedDataTable]
  /// widget unless the data table really is to now show entirely different
  /// data from a new source.
  ///
  /// The [rowsPerPage] and [availableRowsPerPage] must not be null (they
  /// both have defaults, though, so don't have to be specified).
  ///
  /// Themed by [DataTableTheme]. [DataTableThemeData.decoration] is ignored.
  /// To modify the border or background color of the [CustomPaginatedDataTable], use
  /// [CardTheme], since a [Card] wraps the inner [DataTable].
  CustomPaginatedDataTable({
    Key? key,
    this.header,
    this.actions,
    required this.columns,
    this.sortColumnIndex,
    this.sortAscending = true,
    this.onSelectAll,
    this.dataRowHeight = kMinInteractiveDimension,
    this.headingRowHeight = 56.0,
    this.horizontalMargin = 24.0,
    this.columnSpacing = 56.0,
    this.showCheckboxColumn = true,
    this.showFirstLastButtons = false,
    this.initialFirstRowIndex = 0,
    this.onPageChanged,
    this.rowsPerPage = defaultRowsPerPage,
    this.availableRowsPerPage = const <int>[
      defaultRowsPerPage,
      defaultRowsPerPage * 2,
      defaultRowsPerPage * 5,
      defaultRowsPerPage * 10
    ],
    this.onRowsPerPageChanged,
    this.dragStartBehavior = DragStartBehavior.start,
    this.arrowHeadColor,
    required this.source,
    this.checkboxHorizontalMargin,
  })  : assert(actions == null || (header != null)),
        assert(columns.isNotEmpty),
        assert(sortColumnIndex == null ||
            (sortColumnIndex >= 0 && sortColumnIndex < columns.length)),
        assert(rowsPerPage > 0),
        assert(() {
          if (onRowsPerPageChanged != null) {
            assert(availableRowsPerPage.contains(rowsPerPage));
          }
          return true;
        }()),
        super(key: key);

  /// The table card's optional header.
  ///
  /// This is typically a [Text] widget, but can also be a [Row] of
  /// [TextButton]s. To show icon buttons at the top end side of the table with
  /// a header, set the [actions] property.
  ///
  /// If items in the table are selectable, then, when the selection is not
  /// empty, the header is replaced by a count of the selected items. The
  /// [actions] are still visible when items are selected.
  final Widget? header;

  /// Icon buttons to show at the top end side of the table. The [header] must
  /// not be null to show the actions.
  ///
  /// Typically, the exact actions included in this list will vary based on
  /// whether any rows are selected or not.
  ///
  /// These should be size 24.0 with default padding (8.0).
  final List<Widget>? actions;

  /// The configuration and labels for the columns in the table.
  final List<DataColumn> columns;

  /// The current primary sort key's column.
  ///
  /// See [DataTable.sortColumnIndex].
  final int? sortColumnIndex;

  /// Whether the column mentioned in [sortColumnIndex], if any, is sorted
  /// in ascending order.
  ///
  /// See [DataTable.sortAscending].
  final bool sortAscending;

  /// Invoked when the user selects or unselects every row, using the
  /// checkbox in the heading row.
  ///
  /// See [DataTable.onSelectAll].
  final ValueSetter<bool?>? onSelectAll;

  /// The height of each row (excluding the row that contains column headings).
  ///
  /// This value is optional and defaults to kMinInteractiveDimension if not
  /// specified.
  final double dataRowHeight;

  /// The height of the heading row.
  ///
  /// This value is optional and defaults to 56.0 if not specified.
  final double headingRowHeight;

  /// The horizontal margin between the edges of the table and the content
  /// in the first and last cells of each row.
  ///
  /// When a checkbox is displayed, it is also the margin between the checkbox
  /// the content in the first data column.
  ///
  /// This value defaults to 24.0 to adhere to the Material Design specifications.
  ///
  /// If [checkboxHorizontalMargin] is null, then [horizontalMargin] is also the
  /// margin between the edge of the table and the checkbox, as well as the
  /// margin between the checkbox and the content in the first data column.
  final double horizontalMargin;

  /// The horizontal margin between the contents of each data column.
  ///
  /// This value defaults to 56.0 to adhere to the Material Design specifications.
  final double columnSpacing;

  /// {@macro flutter.material.dataTable.showCheckboxColumn}
  final bool showCheckboxColumn;

  /// Flag to display the pagination buttons to go to the first and last pages.
  final bool showFirstLastButtons;

  /// The index of the first row to display when the widget is first created.
  final int? initialFirstRowIndex;

  /// Invoked when the user switches to another page.
  ///
  /// The value is the index of the first row on the currently displayed page.
  final ValueChanged<int>? onPageChanged;

  /// The number of rows to show on each page.
  ///
  /// See also:
  ///
  ///  * [onRowsPerPageChanged]
  ///  * [defaultRowsPerPage]
  final int rowsPerPage;

  /// The default value for [rowsPerPage].
  ///
  /// Useful when initializing the field that will hold the current
  /// [rowsPerPage], when implemented [onRowsPerPageChanged].
  static const int defaultRowsPerPage = 10;

  /// The options to offer for the rowsPerPage.
  ///
  /// The current [rowsPerPage] must be a value in this list.
  ///
  /// The values in this list should be sorted in ascending order.
  final List<int> availableRowsPerPage;

  /// Invoked when the user selects a different number of rows per page.
  ///
  /// If this is null, then the value given by [rowsPerPage] will be used
  /// and no affordance will be provided to change the value.
  final ValueChanged<int?>? onRowsPerPageChanged;

  /// The data source which provides data to show in each row. Must be non-null.
  ///
  /// This object should generally have a lifetime longer than the
  /// [CustomPaginatedDataTable] widget itself; it should be reused each time the
  /// [CustomPaginatedDataTable] constructor is called.
  final DataTableSource source;

  /// {@macro flutter.widgets.scrollable.dragStartBehavior}
  final DragStartBehavior dragStartBehavior;

  /// Horizontal margin around the checkbox, if it is displayed.
  ///
  /// If null, then [horizontalMargin] is used as the margin between the edge
  /// of the table and the checkbox, as well as the margin between the checkbox
  /// and the content in the first data column. This value defaults to 24.0.
  final double? checkboxHorizontalMargin;

  /// Defines the color of the arrow heads in the footer.
  final Color? arrowHeadColor;

  @override
  CustomPaginatedDataTableState createState() =>
      CustomPaginatedDataTableState();
}

/// Holds the state of a [CustomPaginatedDataTable].
///
/// The table can be programmatically paged using the [pageTo] method.
class CustomPaginatedDataTableState extends State<CustomPaginatedDataTable> {
  late int _firstRowIndex;
  late int _rowCount;
  late bool _rowCountApproximate;
  final Map<int, DataRow?> _rows = <int, DataRow?>{};
  final int _pagesToShow = 5;
  @override
  void initState() {
    super.initState();
    _firstRowIndex = PageStorage.of(context)?.readState(context) as int? ??
        widget.initialFirstRowIndex ??
        0;
    widget.source.addListener(_handleDataSourceChanged);
    _handleDataSourceChanged();
  }

  @override
  void didUpdateWidget(CustomPaginatedDataTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      oldWidget.source.removeListener(_handleDataSourceChanged);
      widget.source.addListener(_handleDataSourceChanged);
      _handleDataSourceChanged();
    }
  }

  @override
  void dispose() {
    widget.source.removeListener(_handleDataSourceChanged);
    super.dispose();
  }

  void _handleDataSourceChanged() {
    setState(() {
      _rowCount = widget.source.rowCount;
      _rowCountApproximate = widget.source.isRowCountApproximate;
      _rows.clear();
    });
  }

  /// Ensures that the given row is visible.
  void pageTo(int rowIndex) {
    final oldFirstRowIndex = _firstRowIndex;
    setState(() {
      final rowsPerPage = widget.rowsPerPage;
      _firstRowIndex = (rowIndex ~/ rowsPerPage) * rowsPerPage;
    });
    if ((widget.onPageChanged != null) &&
        (oldFirstRowIndex != _firstRowIndex)) {
      widget.onPageChanged!(_firstRowIndex);
    }
  }

  DataRow _getBlankRowFor(int index) {
    return DataRow.byIndex(
      index: index,
      cells: widget.columns
          .map<DataCell>((DataColumn column) => DataCell.empty)
          .toList(),
    );
  }

  DataRow _getProgressIndicatorRowFor(int index) {
    var haveProgressIndicator = false;
    final cells = widget.columns.map<DataCell>((DataColumn column) {
      if (!column.numeric) {
        haveProgressIndicator = true;
        return const DataCell(CircularProgressIndicator());
      }
      return DataCell.empty;
    }).toList();
    if (!haveProgressIndicator) {
      haveProgressIndicator = true;
      cells[0] = const DataCell(CircularProgressIndicator());
    }
    return DataRow.byIndex(
      index: index,
      cells: cells,
    );
  }

  List<DataRow> _getRows(int firstRowIndex, int rowsPerPage) {
    final result = <DataRow>[];
    final nextPageFirstRowIndex = firstRowIndex + rowsPerPage;
    var haveProgressIndicator = false;
    for (var index = firstRowIndex; index < nextPageFirstRowIndex; index += 1) {
      DataRow? row;
      if (index < _rowCount || _rowCountApproximate) {
        row = _rows.putIfAbsent(index, () => widget.source.getRow(index));
        if (row == null && !haveProgressIndicator) {
          row ??= _getProgressIndicatorRowFor(index);
          haveProgressIndicator = true;
        }
      }
      row ??= _getBlankRowFor(index);
      result.add(row);
    }
    return result;
  }

  void _handleFirst() {
    pageTo(0);
  }

  void _handlePrevious() {
    pageTo(math.max(_firstRowIndex - widget.rowsPerPage, 0));
  }

  void _handleNext() {
    pageTo(_firstRowIndex + widget.rowsPerPage);
  }

  void _handleLast() {
    pageTo(((_rowCount - 1) / widget.rowsPerPage).floor() * widget.rowsPerPage);
  }

  int _getPageCount() {
    return ((_rowCount - 1) / widget.rowsPerPage).ceil();
  }

  int _getCurrentPage() {
    return (_firstRowIndex + 1) ~/ widget.rowsPerPage;
  }

  bool _isNextPageUnavailable() =>
      !_rowCountApproximate &&
      (_firstRowIndex + widget.rowsPerPage >= _rowCount);

  final GlobalKey _tableKey = GlobalKey();

  final pageButtonStyle = TextButton.styleFrom(
    padding: EdgeInsets.zero,
    textStyle: TextStyle(
      color: kOnSurfaceBodyTextColor,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final footerTextStyle = Theme.of(context)
        .textTheme
        .caption!
        .copyWith(color: kOnSurfaceBodyTextColor);

    TextButton pageButton({
      required int page,
      required Function onPressed,
    }) =>
        TextButton(
          style: pageButtonStyle,
          onPressed: () => pageTo(widget.rowsPerPage * page),
          child: Text(
            (page + 1).toString(),
            style: footerTextStyle.copyWith(
              color: page == _getCurrentPage()
                  ? kPrimarySwatch.shade500
                  : kOnSurfaceBodyTextColor,
            ),
          ),
        );
    final footerWidgets = <Widget>[];
    if (widget.onRowsPerPageChanged != null) {
      final List<Widget> availableRowsPerPage = widget.availableRowsPerPage
          .where(
              (int value) => value <= _rowCount || value == widget.rowsPerPage)
          .map<DropdownMenuItem<int>>((int value) {
        return DropdownMenuItem<int>(
          value: value,
          child: Text('$value'),
        );
      }).toList();
      footerWidgets.addAll(<Widget>[
        Container(
          width: 14.0,
        ), // to match trailing padding in case we overflow and end up scrolling
        Text(
          'Rows Per Page',
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(
              minWidth: 64.0), // 40.0 for the text, 24.0 for the icon
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                style: footerTextStyle,
                items: availableRowsPerPage.cast<DropdownMenuItem<int>>(),
                value: widget.rowsPerPage,
                onChanged: widget.onRowsPerPageChanged,
              ),
            ),
          ),
        ),
      ]);
    }
    footerWidgets.addAll(<Widget>[
      Container(width: 32.0),
      Text(
        '${_firstRowIndex + 1} - ${_firstRowIndex + widget.rowsPerPage} of $_rowCount',
      ),
      Container(width: 32.0),
      if (widget.showFirstLastButtons)
        IconButton(
          icon: Icon(Icons.skip_previous, color: widget.arrowHeadColor),
          padding: EdgeInsets.zero,
          tooltip: 'Go to first',
          onPressed: _firstRowIndex <= 0 ? null : _handleFirst,
        ),
      IconButton(
        icon: Icon(Icons.chevron_left, color: widget.arrowHeadColor),
        padding: EdgeInsets.zero,
        tooltip: 'Previous',
        onPressed: _firstRowIndex <= 0 ? null : _handlePrevious,
      ),
      Row(
        children: [
          if (_getPageCount() > _pagesToShow) ...[
            if (_getCurrentPage() < (_pagesToShow - 1)) ...[
              for (var i = 0; i < _pagesToShow; i++)
                pageButton(
                  page: i,
                  onPressed: () => pageTo(widget.rowsPerPage * i),
                ),
              Text('...'),
              pageButton(
                page: _getPageCount(),
                onPressed: () => _handleLast(),
              ),
            ] else if (_getCurrentPage() >= (_pagesToShow - 1) &&
                _getCurrentPage() < _getPageCount() - _pagesToShow) ...[
              pageButton(
                page: 0,
                onPressed: () => _handleFirst(),
              ),
              Text('...'),
              for (var i = _getCurrentPage() - 2;
                  i <= _getCurrentPage() + 2;
                  i++)
                pageButton(
                  page: i,
                  onPressed: () => pageTo(widget.rowsPerPage * i),
                ),
              Text('...'),
              pageButton(
                page: _getPageCount(),
                onPressed: () => _handleLast(),
              ),
            ] else ...[
              pageButton(
                page: 0,
                onPressed: () => _handleFirst(),
              ),
              Text('...'),
              for (var i = _getPageCount() - _pagesToShow;
                  i <= _getPageCount();
                  i++)
                pageButton(
                  page: i,
                  onPressed: () => pageTo(widget.rowsPerPage * i),
                ),
            ]
          ] else
            for (var i = 0; i < _getPageCount(); i++)
              pageButton(
                page: i,
                onPressed: () => pageTo(widget.rowsPerPage * i),
              ),
        ],
      ),
      IconButton(
        icon: Icon(Icons.chevron_right, color: widget.arrowHeadColor),
        padding: EdgeInsets.zero,
        tooltip: 'Next',
        onPressed: _isNextPageUnavailable() ? null : _handleNext,
      ),
      if (widget.showFirstLastButtons)
        IconButton(
          icon: Icon(Icons.skip_next, color: widget.arrowHeadColor),
          padding: EdgeInsets.zero,
          tooltip: 'Go to Last',
          onPressed: _isNextPageUnavailable() ? null : _handleLast,
        ),
      Container(width: 14.0),
    ]);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              dragStartBehavior: widget.dragStartBehavior,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.minWidth),
                child: Theme(
                  data: Theme.of(context),
                  child: DataTable(
                    key: _tableKey,
                    columns: widget.columns,
                    sortColumnIndex: widget.sortColumnIndex,
                    sortAscending: widget.sortAscending,
                    onSelectAll: widget.onSelectAll,
                    dataRowHeight: widget.dataRowHeight,
                    headingRowHeight: widget.headingRowHeight,
                    horizontalMargin: widget.horizontalMargin,
                    checkboxHorizontalMargin: widget.checkboxHorizontalMargin,
                    columnSpacing: widget.columnSpacing,
                    showCheckboxColumn: widget.showCheckboxColumn,
                    showBottomBorder: true,
                    rows: _getRows(_firstRowIndex, widget.rowsPerPage),
                  ),
                ),
              ),
            ),
            DefaultTextStyle(
              style: footerTextStyle,
              child: IconTheme.merge(
                data: const IconThemeData(
                  opacity: 0.54,
                ),
                child: SizedBox(
                  height: 56.0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: footerWidgets,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
