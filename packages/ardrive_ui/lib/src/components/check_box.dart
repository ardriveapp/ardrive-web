import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_ui/src/constants/size_constants.dart';
import 'package:flutter/material.dart';

// TODO: We only set the checked state on the initial state, to change the state the user must interact with the checkbox.
// TODO: We may want to add a way to change the state of the checkbox from outside.
class ArDriveCheckBox extends StatefulWidget {
  const ArDriveCheckBox({
    super.key,
    this.checked = false,
    this.isDisabled = false,
    this.isIndeterminate = false,
    this.title,
    this.titleStyle,
    this.onChange,
    this.titleWidget,
  });

  /// Initial state of the checkbox.
  final bool checked;
  final bool isDisabled;

  /// If true, the checkbox will be rendered as indeterminate.
  final bool isIndeterminate;
  final String? title;

  /// A widget that will be used as the title of the checkbox.
  /// It only shows if [title] is null.
  final Widget? titleWidget;
  final TextStyle? titleStyle;
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
    if (checked && !widget.isDisabled) {
      state = CheckBoxState.checked;
    } else if (widget.isDisabled) {
      state = CheckBoxState.disabled;
    } else if (widget.isIndeterminate) {
      state = CheckBoxState.indeterminate;
    } else {
      state = CheckBoxState.normal;
    }

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
            setState(() {
              checked = !checked;
            });
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
      child: ArDriveClickArea(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            state == CheckBoxState.indeterminate
                ? ArDriveIcon(
                    icon: ArDriveIconsData.minus_rectangle,
                    size: 22,
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeFgDefault,
                  )
                : AnimatedContainer(
                    height: 18.5,
                    width: 18.5,
                    margin: const EdgeInsets.fromLTRB(3.25, 3.5, 5, 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(checkboxBorderRadius),
                      border: Border.all(
                        color: _boxColor(),
                        width: 2,
                      ),
                      color: _backgroundColor(),
                    ),
                    duration: const Duration(milliseconds: 300),
                    child: checked
                        ? ArDriveIcon(
                            icon: ArDriveIconsData.checkmark,
                            size: 12,
                            color: _checkColor(),
                          )
                        : null,
                  ),
            if (_buildTitle() != null) ...[
              const SizedBox(width: 8.0),
              _buildTitle()!,
            ]
          ],
        ),
      ),
    );
  }

  Widget? _buildTitle() {
    if (widget.title != null) {
      return Flexible(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 4.0),
          child: Text(
            widget.title!,
            style: widget.titleStyle ??
                ArDriveTypography.body.bodyRegular(
                  color: _textColor(),
                ),
          ),
        ),
      );
    }

    if (widget.title == null && widget.titleWidget != null) {
      return widget.titleWidget!;
    }

    return null;
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
        return ArDriveTheme.of(context).themeData.colors.themeFgDefault;
    }
  }

  Color _backgroundColor() {
    switch (state) {
      case CheckBoxState.indeterminate:
      case CheckBoxState.checked:
      case CheckBoxState.hover:
        return ArDriveTheme.of(context).themeData.colors.themeFgDefault;
      case CheckBoxState.disabled:
        return Colors.transparent;

      case CheckBoxState.normal:
        return Colors.transparent;
    }
  }

  Color _checkColor() {
    switch (state) {
      case CheckBoxState.indeterminate:
      case CheckBoxState.checked:
      case CheckBoxState.hover:
        return ArDriveTheme.of(context).themeData.colors.themeBgSubtle;
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
