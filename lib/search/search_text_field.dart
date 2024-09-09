import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class SearchTextField extends StatelessWidget {
  const SearchTextField({
    super.key,
    this.controller,
    required this.onFieldSubmitted,
    this.onChanged,
    this.hintText,
    this.labelText,
  });

  final TextEditingController? controller;
  final Function(String text) onFieldSubmitted;
  final Function(String text)? onChanged;
  final String? hintText;
  final String? labelText;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return ArDriveTextFieldNew(
      controller: controller,
      hintText: hintText,
      label: labelText,
      onChanged: onChanged,
      prefixIcon: Padding(
        padding: const EdgeInsets.only(right: 8.0, left: 16),
        child: Icon(
          Icons.search,
          size: 20,
          color: colorTokens.textMid,
        ),
      ),
      onTapOutside: (_) {
        FocusScope.of(context).unfocus();
      },
      suffixIcon: Transform(
        // move 4 pixels bottom
        transform: Matrix4.translationValues(0.0, 4.0, 0.0),
        child: ArDriveClickArea(
          child: GestureDetector(
            child: Icon(
              Icons.close,
              size: 20,
              color: colorTokens.textMid,
            ),
            onTap: () {
              controller?.clear();
              onChanged?.call('');
            },
          ),
        ),
      ),
      hintStyle: typography.paragraphNormal(
          color: colorTokens.textMid, fontWeight: ArFontWeight.semiBold),
      onFieldSubmitted: onFieldSubmitted,
    );
  }
}
