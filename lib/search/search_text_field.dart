import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class SearchTextField extends StatelessWidget {
  const SearchTextField({
    super.key,
    this.controller,
    required this.onFieldSubmitted,
    this.onChanged,
    this.onEditingComplete,
    this.focusNode,
    this.hintText,
    this.labelText,
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final Function(String text) onFieldSubmitted;
  final Function(String text)? onChanged;

  /// See [ArDriveTextFieldNew.onEditingComplete]: set it to keep focus in the
  /// field when Enter is pressed.
  final VoidCallback? onEditingComplete;
  final FocusNode? focusNode;
  final String? hintText;
  final String? labelText;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return ArDriveTextFieldNew(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      hintText: hintText,
      label: labelText,
      onChanged: onChanged,
      onEditingComplete: onEditingComplete,
      prefixIcon: Padding(
        padding: const EdgeInsets.only(right: 8.0, left: 16),
        child: Icon(
          Icons.search,
          size: 20,
          color: colorTokens.textMid,
        ),
      ),
      onTapOutside: (_) {
        focusNode != null
            ? focusNode!.unfocus()
            : FocusScope.of(context).unfocus();
      },
      // Only when there is something to clear: an x in an empty field offers
      // to do nothing.
      suffixIcon: controller == null
          ? null
          : ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller!,
              builder: (context, value, _) {
                // The x's room is kept when there is nothing to clear, so
                // the field doesn't jump when it appears.
                if (value.text.isEmpty) {
                  return const SizedBox.square(dimension: 20);
                }

                return Transform(
                  // move 4 pixels bottom
                  transform: Matrix4.translationValues(0.0, 4.0, 0.0),
                  child: Semantics(
                    button: true,
                    label: appLocalizationsOf(context).searchClear,
                    child: ArDriveFocusable(
                      onActivate: () {
                        controller?.clear();
                        onChanged?.call('');
                      },
                      child: ArDriveClickArea(
                        tooltip: appLocalizationsOf(context).searchClear,
                        child: GestureDetector(
                          // ArDrive's own glyph, as every other close is.
                          child: ArDriveIcons.x(
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
                  ),
                );
              },
            ),
      hintStyle: typography.paragraphNormal(
          color: colorTokens.textMid, fontWeight: ArFontWeight.semiBold),
      onFieldSubmitted: onFieldSubmitted,
    );
  }
}
