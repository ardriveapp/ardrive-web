import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class ArDrivePaginationDots extends StatefulWidget {
  const ArDrivePaginationDots({
    super.key,
    required this.numberOfPages,
    required this.currentPage,
  });

  final int numberOfPages;
  final int currentPage;

  @override
  State<ArDrivePaginationDots> createState() => _ArDrivePaginationDotsState();
}

class _ArDrivePaginationDotsState extends State<ArDrivePaginationDots> {
  int selectedPage = 0;
  late int _numberOfPages;

  @override
  void initState() {
    _numberOfPages = widget.numberOfPages;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        _numberOfPages,
        (index) {
          return Padding(
            padding: EdgeInsets.only(
              right: index < _numberOfPages - 1 ? 16 : 0,
            ),
            child: _buildPaginationDot(index),
          );
        },
      ),
    );
  }

  Widget _buildPaginationDot(int index) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: widget.currentPage == index
            ? ArDriveTheme.of(context).themeData.colors.themeErrorOnEmphasis
            : ArDriveTheme.of(context).themeData.colors.themeFgDefault,
        shape: BoxShape.circle,
      ),
    );
  }
}
