import 'dart:math' as math;

import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:ardrive_ui_library/utils/intersperse.dart';
import 'package:flutter/material.dart';

class NumberedPageIndicator extends StatelessWidget {
  final bool isRowCountApproximate;
  final int rowCount;
  final int firstRowIndex;
  final Function(int) pageTo;
  final int rowsPerPage;
  final bool showFirstAndLastButtons;
  final String? goToFirstTooltip;
  final String? goToLastTooltip;
  final String? nextTooltip;
  final String? previousTooltip;

  final int pagesToShow = 5;
  final double size = 16;

  const NumberedPageIndicator({
    Key? key,
    required this.isRowCountApproximate,
    required this.rowCount,
    required this.firstRowIndex,
    required this.pageTo,
    required this.rowsPerPage,
    required this.showFirstAndLastButtons,
    this.goToFirstTooltip,
    this.goToLastTooltip,
    this.nextTooltip,
    this.previousTooltip,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    pageButtonStyle() {
      return TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: Size(size, size),
        textStyle: TextStyle(
          color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
        ),
      );
    }

    bool isNextPageUnavailable =
        !isRowCountApproximate && (firstRowIndex + rowsPerPage >= rowCount);

    int pageCount = (rowCount / rowsPerPage).ceil();

    int currentPage = (firstRowIndex + 1) ~/ rowsPerPage;

    void goToFirst() => pageTo(0);

    void goToPrevious() => pageTo(math.max(firstRowIndex - rowsPerPage, 0));

    void goToNext() => pageTo(firstRowIndex + rowsPerPage);

    void goToEnd() =>
        pageTo(((rowCount - 1) / rowsPerPage).floor() * rowsPerPage);

    const ellipsisSeparator = Text('...');

    const pageNumberSeparator = SizedBox.square(dimension: 8);

    TextButton pageButton({
      required int page,
      required Function onPressed,
    }) {
      return TextButton(
        style: pageButtonStyle(),
        onPressed: () => pageTo(rowsPerPage * page),
        child: Text(
          (page + 1).toString(),
          style: ArDriveTypography.body.bodyRegular().copyWith(
                fontSize: size,
                color: page == currentPage
                    ? ArDriveTheme.of(context).themeData.colors.themeFgDefault
                    : ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeAccentMuted,
              ),
        ),
      );
    }

    Widget pageRow(int pagesToShow) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (pageCount > pagesToShow) ...[
            if (currentPage < (pagesToShow - 1)) ...[
              for (var i = 0; i < pagesToShow; i++)
                pageButton(
                  page: i,
                  onPressed: () => pageTo(rowsPerPage * i),
                ),
              ellipsisSeparator,
              pageButton(
                page: pageCount - 1,
                onPressed: goToEnd,
              ),
            ] else if (currentPage >= (pagesToShow - 1) &&
                currentPage < pageCount - pagesToShow) ...[
              pageButton(
                page: 0,
                onPressed: goToFirst,
              ),
              ellipsisSeparator,
              for (var i = currentPage - 2; i <= currentPage + 2; i++)
                pageButton(
                  page: i,
                  onPressed: () => pageTo(rowsPerPage * i),
                ),
              ellipsisSeparator,
              pageButton(
                page: pageCount - 1,
                onPressed: goToEnd,
              ),
            ] else ...[
              pageButton(
                page: 0,
                onPressed: goToFirst,
              ),
              ellipsisSeparator,
              for (var i = pageCount - pagesToShow; i < pageCount; i++)
                pageButton(
                  page: i,
                  onPressed: () => pageTo(rowsPerPage * i),
                ),
            ]
          ] else
            for (var i = 0; i < pageCount; i++)
              pageButton(
                page: i,
                onPressed: () => pageTo(rowsPerPage * i),
              ),
        ].intersperse(pageNumberSeparator).toList(),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: size),
      child: Row(
        children: [
          IconButton(
            iconSize: size + 4,
            icon: const Icon(
              Icons.skip_previous,
            ),
            constraints: const BoxConstraints(maxWidth: 20),
            padding: EdgeInsets.zero,
            onPressed: () => firstRowIndex <= 0 ? null : goToFirst(),
            tooltip: goToFirstTooltip,
          ),
          IconButton(
            iconSize: size + 4,
            icon: const Icon(
              Icons.chevron_left,
            ),
            constraints: const BoxConstraints(maxWidth: 20),
            padding: EdgeInsets.zero,
            onPressed: () => firstRowIndex <= 0 ? null : goToPrevious(),
            tooltip: previousTooltip,
          ),
          pageRow(pagesToShow),
          IconButton(
            iconSize: size + 4,
            icon: const Icon(
              Icons.chevron_right,
            ),
            constraints: const BoxConstraints(maxWidth: 20),
            padding: EdgeInsets.zero,
            onPressed: () => isNextPageUnavailable ? null : goToNext(),
            tooltip: nextTooltip,
          ),
          if (showFirstAndLastButtons)
            IconButton(
              iconSize: size + 4,
              icon: const Icon(
                Icons.skip_next,
              ),
              constraints: const BoxConstraints(maxWidth: 20),
              padding: EdgeInsets.zero,
              onPressed: () => isNextPageUnavailable ? null : goToEnd(),
              tooltip: goToLastTooltip,
            ),
          Container(width: 14.0),
        ],
      ),
    );
  }
}
