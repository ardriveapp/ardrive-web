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
    this.label,
    this.isFieldRequired = false,
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
  final String? label;
  final bool isFieldRequired;

  @override
  State<ArDriveTextField> createState() => ArDriveTextFieldState();
}

enum TextFieldState { unfocused, focused, disabled, error, success }

@visibleForTesting
class ArDriveTextFieldState extends State<ArDriveTextField> {
  @visibleForTesting
  late TextFieldState textFieldState;

  @override
  void initState() {
    textFieldState = TextFieldState.unfocused;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _textFieldLabel(widget.label!),
              ),
            ),
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
              setState(
                () {
                  final textIsValid = widget.validator?.call(text);

                  if (text.isEmpty) {
                    textFieldState = TextFieldState.focused;
                  } else if (textIsValid != null && !textIsValid) {
                    textFieldState = TextFieldState.error;
                  } else if (textIsValid != null && textIsValid) {
                    textFieldState = TextFieldState.success;
                  }

                  widget.onChanged?.call(text);
                },
              );
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
              fillColor: ArDriveTheme.of(context)
                  .themeData
                  .colors
                  .themeInputBackground,
            ),
          ),
          if (widget.errorMessage != null) _errorMessage(widget.errorMessage!),
          if (widget.successMessage != null)
            _successMessage(widget.successMessage!),
        ],
      ),
    );
  }

  Widget _errorMessage(String message) {
    return AnimatedTextFieldLabel(
      text: message,
      showing: textFieldState == TextFieldState.error,
      color: ArDriveTheme.of(context).themeData.colors.themeErrorDefault,
    );
  }

  Widget _textFieldLabel(String message) {
    return Row(
      children: [
        TextFieldLabel(
          text: message,
          bold: true,
          color: widget.isFieldRequired
              ? ArDriveTheme.of(context).themeData.colors.themeFgDefault
              : ArDriveTheme.of(context).themeData.colors.themeAccentDefault,
        ),
        if (widget.isFieldRequired)
          Text(
            '*',
            style: ArDriveTypography.body.bodyRegular(
              color:
                  ArDriveTheme.of(context).themeData.colors.themeAccentDefault,
            ),
          )
      ],
    );
  }

  Widget _successMessage(String message) {
    return AnimatedTextFieldLabel(
      text: message,
      showing: textFieldState == TextFieldState.success,
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
    if (textFieldState == TextFieldState.success) {
      return _getSuccessBorder();
    } else if (textFieldState == TextFieldState.error) {
      return _getErrorBorder();
    }
    return _getBorder(
      ArDriveTheme.of(context).themeData.colors.themeBorderDefault,
    );
  }

  InputBorder _getFocusedBoder() {
    if (textFieldState == TextFieldState.success) {
      return _getSuccessBorder();
    } else if (textFieldState == TextFieldState.error) {
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

@visibleForTesting
class AnimatedTextFieldLabel extends StatefulWidget {
  const AnimatedTextFieldLabel({
    super.key,
    required this.text,
    required this.showing,
    required this.color,
  });

  final String text;
  final bool showing;
  final Color color;

  @override
  State<AnimatedTextFieldLabel> createState() => _AnimatedTextFieldLabelState();
}

class _AnimatedTextFieldLabelState extends State<AnimatedTextFieldLabel> {
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
          opacity: _visible ? 1.0 : 0.0,
          duration: Duration(milliseconds: !_visible ? 100 : 300),
          child: TextFieldLabel(
            color: widget.color,
            text: widget.text,
          ),
        ),
      ),
    );
  }
}

class TextFieldLabel extends StatelessWidget {
  const TextFieldLabel({
    super.key,
    required this.text,
    required this.color,
    this.bold = false,
  });
  final String text;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return AutoSizeText(
      text,
      style: bold
          ? ArDriveTypography.body.bodyBold(
              color: color,
            )
          : ArDriveTypography.body.bodyRegular(
              color: color,
            ),
    );
  }
}
