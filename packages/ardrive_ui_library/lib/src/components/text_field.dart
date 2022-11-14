import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ArDriveTextField extends StatefulWidget {
  const ArDriveTextField({
    super.key,
    this.isEnabled = true,
    this.validator,
    this.hintText,
    this.onChanged,
    this.obscureText = false,
    this.autofillHints,
    this.autovalidateMode,
    this.errorMessage,
    this.successMessage,
    this.autocorrect = true,
    this.autofocus = false,
    this.controller,
    this.initialValue,
    this.inputFormatters,
    this.keyboardType,
    this.onTap,
    this.onFieldSubmitted,
    this.focusNode,
    this.maxLength,
  });

  final bool isEnabled;
  final bool Function(String?)? validator;
  final Function(String)? onChanged;
  final String? hintText;
  final bool obscureText;
  final List<String>? autofillHints;
  final AutovalidateMode? autovalidateMode;
  final String? errorMessage;
  final String? successMessage;
  final bool autocorrect;
  final bool autofocus;
  final String? initialValue;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final Function()? onTap;
  final Function(String)? onFieldSubmitted;
  final int? maxLength;
  final FocusNode? focusNode;

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
          controller: widget.controller,
          autocorrect: widget.autocorrect,
          autofocus: widget.autofocus,
          initialValue: widget.initialValue,
          keyboardType: widget.keyboardType,
          inputFormatters: widget.inputFormatters,
          onTap: widget.onTap,
          onFieldSubmitted: widget.onFieldSubmitted,
          maxLength: widget.maxLength,
          focusNode: widget.focusNode,
          key: widget.key,
          obscureText: widget.obscureText,
          style: ArDriveTypography.body.inputLargeRegular(
            color: ArDriveTheme.of(context).themeData.colors.themeInputText,
          ),
          autovalidateMode: AutovalidateMode.always,
          onChanged: (text) {
            setState(() {
              final textIsValid = widget.validator?.call(text);

              if (text.isEmpty) {
                _state = ArDriveTextFieldState.focused;
              } else if (textIsValid != null && !textIsValid) {
                _state = ArDriveTextFieldState.error;
              } else if (textIsValid != null && textIsValid) {
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
        if (widget.errorMessage != null) _errorMessage(widget.errorMessage!),
        if (widget.successMessage != null)
          _successMessage(widget.successMessage!),
      ],
    );
  }

  Widget _errorMessage(String message) {
    return _BottomText(
        text: message,
        showing: _state == ArDriveTextFieldState.error,
        color: ArDriveTheme.of(context).themeData.colors.themeErrorDefault);
  }

  Widget _successMessage(String message) {
    return _BottomText(
      text: message,
      showing: _state == ArDriveTextFieldState.success,
      color: ArDriveTheme.of(context).themeData.colors.themeSuccessDefault,
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

class _BottomText extends StatefulWidget {
  const _BottomText({
    required this.text,
    required this.showing,
    required this.color,
  });

  final String text;
  final bool showing;
  final Color color;

  @override
  State<_BottomText> createState() => __BottomTextState();
}

class __BottomTextState extends State<_BottomText> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showing) {
      _visible = false;
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedContainer(
        onEnd: () => setState(() {
          _visible = !_visible;
        }),
        duration: const Duration(milliseconds: 300),
        height: widget.showing ? 35 : 0,
        width: double.infinity,
        child: AnimatedOpacity(
          // If the widget is visible, animate to 0.0 (invisible).
          // If the widget is hidden, animate to 1.0 (fully visible).
          opacity: _visible ? 1.0 : 0.0,
          duration: Duration(milliseconds: !_visible ? 100 : 300),
          // The green box must be a child of the AnimatedOpacity widget.
          child: AutoSizeText(
            widget.text,
            style: ArDriveTypography.body.bodyRegular(
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }
}
