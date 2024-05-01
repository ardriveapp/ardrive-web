import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class SearchTextField extends StatelessWidget {
  const SearchTextField({
    super.key,
    required this.controller,
    required this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final Function(String text) onFieldSubmitted;
  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return ArDriveTextFieldNew(
      controller: controller,
      hintText: 'Search',
      prefixIcon: Padding(
        padding: const EdgeInsets.only(right: 8.0, left: 16),
        child: Icon(
          Icons.search,
          size: 20,
          color: colorTokens.textMid,
        ),
      ),
      hintStyle: typography.paragraphNormal(
          color: colorTokens.textMid, fontWeight: ArFontWeight.semiBold),
      onFieldSubmitted: onFieldSubmitted,
    );
  }
}
