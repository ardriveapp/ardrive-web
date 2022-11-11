import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';

class ArDriveTextField extends StatefulWidget {
  const ArDriveTextField({
    super.key,
    this.isEnabled = true,
    this.validator,
    this.hintText,
    this.onChanged,
    this.obscureText = false,
    this.autofillHints,
  });

  final bool isEnabled;
  final String? Function(String?)? validator;
  final Function(String)? onChanged;
  final String? hintText;
  final bool obscureText;
  final List<String>? autofillHints;

  @override
  State<ArDriveTextField> createState() => _ArDriveTextFieldState();
}

enum ArDriveTextFieldState { unfocused, focused, disabled, error, success }

class _ArDriveTextFieldState extends State<ArDriveTextField> {
  late ArDriveTextFieldState _state;

  @override
  void initState() {
    _state = ArDriveTextFieldState.unfocused;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          style: ArDriveTypography.body.inputLargeRegular(
            color: ArDriveTheme.of(context).themeData.colors.themeInputText,
          ),
          autovalidateMode: AutovalidateMode.always,
          // validator: (s) {
          //   return widget.validator?.call(s);
          // },
          onChanged: (text) {
            // if (widget.onChanged != null) {
            //   widget.onChanged(text);
            // }
            setState(() {
              final validationMessage = widget.validator?.call(text);
              print(validationMessage);
              if (validationMessage != null) {
                _state = ArDriveTextFieldState.error;
              } else if (text.isEmpty) {
                _state = ArDriveTextFieldState.focused;
              } else if (widget.validator != null) {
                _state = ArDriveTextFieldState.success;
              }
              widget.onChanged?.call(text);
            });
          },
          autofillHints: widget.autofillHints,
          enabled: widget.isEnabled,
          decoration: InputDecoration(
            errorStyle: const TextStyle(height: 0),
            hintText: widget.hintText,
            hintStyle: ArDriveTypography.body
                .inputLargeRegular(color: _hintTextColor()),
            enabledBorder: _getEnabledBorder(),
            focusedBorder: _getFocusedBoder(),
            disabledBorder: _getDisabledBorder(),
            filled: true,
            fillColor:
                ArDriveTheme.of(context).themeData.colors.themeInputBackground,
          ),
        ),
        _errorMessage(),
        _successMessage(),
      ],
    );
  }

  Widget _errorMessage() {
    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: _state == ArDriveTextFieldState.error ? 35 : 0,
        child: Text(
          'Error message',
          style: ArDriveTypography.body.bodyRegular(
            color: ArDriveTheme.of(context).themeData.colors.themeErrorDefault,
          ),
        ),
      ),
    );
  }

  Widget _successMessage() {
    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: _state == ArDriveTextFieldState.success ? 35 : 0,
        child: Text(
          'Success message',
          style: ArDriveTypography.body.bodyRegular(
            color:
                ArDriveTheme.of(context).themeData.colors.themeSuccessDefault,
          ),
        ),
      ),
    );
  }

  InputBorder _getBorder(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: BorderSide(color: color, width: 2),
    );
  }

  InputBorder _getEnabledBorder() {
    if (_state == ArDriveTextFieldState.success) {
      return _getSuccessBorder();
    } else if (_state == ArDriveTextFieldState.error) {
      return _getErrorBorder();
    }
    return _getBorder(
      ArDriveTheme.of(context).themeData.colors.themeBorderDefault,
    );
  }

  InputBorder _getFocusedBoder() {
    if (_state == ArDriveTextFieldState.success) {
      return _getSuccessBorder();
    } else if (_state == ArDriveTextFieldState.error) {
      return _getErrorBorder();
    }

    return _getBorder(
      ArDriveTheme.of(context).themeData.colors.themeAccentEmphasis,
    );
  }

  InputBorder _getDisabledBorder() {
    return _getBorder(
      ArDriveTheme.of(context).themeData.colors.themeInputBorderDisabled,
    );
  }

  InputBorder _getErrorBorder() {
    return _getBorder(
      ArDriveTheme.of(context).themeData.colors.themeErrorOnEmphasis,
    );
  }

  InputBorder _getSuccessBorder() {
    return _getBorder(
      ArDriveTheme.of(context).themeData.colors.themeSuccessEmphasis,
    );
  }

  Color _hintTextColor() {
    if (widget.isEnabled) {
      return ArDriveTheme.of(context).themeData.colors.themeInputPlaceholder;
    }
    return ArDriveTheme.of(context).themeData.colors.themeFgDisabled;
  }
}
