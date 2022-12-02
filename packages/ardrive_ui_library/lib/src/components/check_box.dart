import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:ardrive_ui_library/src/constants/size_constants.dart';
import 'package:flutter/material.dart';

class ArDriveCheckBox extends StatefulWidget {
  const ArDriveCheckBox({
    super.key,
    this.checked = false,
    this.isDisabled = false,
    this.isIndeterminate = false,
    required this.title,
    this.onChange,
  });

  final bool checked;
  final bool isDisabled;
  final bool isIndeterminate;
  final String title;
  final Function(bool value)? onChange;

  @override
  State<ArDriveCheckBox> createState() => ArDriveCheckBoxState();
}

enum CheckBoxState { normal, hover, indeterminate, checked, disabled }

@visibleForTesting
class ArDriveCheckBoxState extends State<ArDriveCheckBox> {
  @visibleForTesting
  late CheckBoxState state;

  @visibleForTesting
  late bool checked;

  @override
  void initState() {
    checked = widget.checked;
    if (checked && !widget.isDisabled && !widget.isIndeterminate) {
      state = CheckBoxState.checked;
    } else if (widget.isDisabled) {
      state = CheckBoxState.disabled;
    } else if (widget.isIndeterminate) {
      state = CheckBoxState.indeterminate;
    } else {
      state = CheckBoxState.normal;
    }

    // You can't have the checkbox checked and with the indeterminate state.
    assert(!(widget.checked && widget.isIndeterminate));

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        switch (state) {
          case CheckBoxState.normal:
          case CheckBoxState.hover:
            setState(() {
              state = CheckBoxState.checked;
              checked = true;
            });
            break;
          case CheckBoxState.indeterminate:
            break;
          case CheckBoxState.checked:
            setState(() {
              state = CheckBoxState.normal;
              checked = false;
            });
            break;
          case CheckBoxState.disabled:
            break;
        }
        widget.onChange?.call(checked);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AnimatedContainer(
            height: checkboxSize,
            width: checkboxSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(checkboxBorderRadius),
              border: state == CheckBoxState.indeterminate
                  ? null
                  : Border.all(
                      color: _boxColor(),
                      width: 2,
                    ),
            ),
            duration: const Duration(milliseconds: 300),
            child: checked
                ? Padding(
                    padding: const EdgeInsets.all(3),
                    child: ArDriveIcons.checked(
                      color: _checkColor(),
                    ),
                  )
                : state == CheckBoxState.indeterminate
                    ? ArDriveIcons.indeterminateIndicator(
                        color: _checkColor(),
                      )
                    : null,
          ),
          const SizedBox(
            width: 8,
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Text(
              widget.title,
              style: ArDriveTypography.body.bodyRegular(
                color: _textColor(),
              ),
            ),
          )
        ],
      ),
    );
  }

  Color _boxColor() {
    switch (state) {
      case CheckBoxState.indeterminate:
      case CheckBoxState.checked:
      case CheckBoxState.hover:
        return ArDriveTheme.of(context).themeData.colors.themeFgDefault;
      case CheckBoxState.disabled:
        return ArDriveTheme.of(context).themeData.colors.themeFgDisabled;
      case CheckBoxState.normal:
        return ArDriveTheme.of(context).themeData.colors.themeAccentDefault;
    }
  }

  Color _checkColor() {
    switch (state) {
      case CheckBoxState.indeterminate:
      case CheckBoxState.checked:
      case CheckBoxState.hover:
        return ArDriveTheme.of(context).themeData.colors.themeFgDefault;
      case CheckBoxState.disabled:
        return ArDriveTheme.of(context).themeData.colors.themeFgDisabled;
      case CheckBoxState.normal:
        return ArDriveTheme.of(context).themeData.colors.themeAccentDefault;
    }
  }

  Color _textColor() {
    switch (state) {
      case CheckBoxState.indeterminate:
      case CheckBoxState.checked:
      case CheckBoxState.hover:
      case CheckBoxState.normal:
        return ArDriveTheme.of(context).themeData.colors.themeFgDefault;
      case CheckBoxState.disabled:
        return ArDriveTheme.of(context).themeData.colors.themeFgDisabled;
    }
  }
}
