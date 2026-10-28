import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';

/// A field's label that shrinks to fit its width.
class TextFieldLabel extends StatelessWidget {
  const TextFieldLabel({
    super.key,
    required this.text,
    required this.style,
  });
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return AutoSizeText(text, style: style);
  }
}

class ArDriveTextFieldTheme {
  final Color inputTextColor;
  final Color inputBackgroundColor;
  final Color inputDisabledBorderColor;
  final Color errorColor;
  final Color requiredLabelColor;
  final Color labelColor;
  final Color successColor;
  final Color defaultBorderColor;
  final Color errorBorderColor;
  final Color successBorderColor;
  final Color inputPlaceholderColor;
  final Color disabledTextColor;
  final TextStyle inputTextStyle;
  final TextStyle? labelStyle;
  final TextStyle? errorLabelStyle;
  final EdgeInsets? contentPadding;

  const ArDriveTextFieldTheme({
    required this.inputTextColor,
    required this.inputBackgroundColor,
    required this.inputDisabledBorderColor,
    required this.errorColor,
    required this.requiredLabelColor,
    required this.labelColor,
    required this.successColor,
    required this.defaultBorderColor,
    required this.errorBorderColor,
    required this.successBorderColor,
    required this.inputPlaceholderColor,
    required this.disabledTextColor,
    required this.inputTextStyle,
    this.labelStyle,
    this.contentPadding,
    this.errorLabelStyle,
  });

  // copy with
  ArDriveTextFieldTheme copyWith({
    Color? inputTextColor,
    Color? inputBackgroundColor,
    Color? inputDisabledBorderColor,
    Color? errorColor,
    Color? requiredLabelColor,
    Color? labelColor,
    Color? successColor,
    Color? defaultBorderColor,
    Color? errorBorderColor,
    Color? successBorderColor,
    Color? inputPlaceholderColor,
    Color? disabledTextColor,
    TextStyle? inputTextStyle,
    TextStyle? labelStyle,
    EdgeInsets? contentPadding,
  }) {
    return ArDriveTextFieldTheme(
      inputTextColor: inputTextColor ?? this.inputTextColor,
      inputBackgroundColor: inputBackgroundColor ?? this.inputBackgroundColor,
      inputDisabledBorderColor:
          inputDisabledBorderColor ?? this.inputDisabledBorderColor,
      errorColor: errorColor ?? this.errorColor,
      requiredLabelColor: requiredLabelColor ?? this.requiredLabelColor,
      labelColor: labelColor ?? this.labelColor,
      successColor: successColor ?? this.successColor,
      defaultBorderColor: defaultBorderColor ?? this.defaultBorderColor,
      errorBorderColor: errorBorderColor ?? this.errorBorderColor,
      successBorderColor: successBorderColor ?? this.successBorderColor,
      inputPlaceholderColor:
          inputPlaceholderColor ?? this.inputPlaceholderColor,
      disabledTextColor: disabledTextColor ?? this.disabledTextColor,
      inputTextStyle: inputTextStyle ?? this.inputTextStyle,
      labelStyle: labelStyle ?? this.labelStyle,
      contentPadding: contentPadding ?? this.contentPadding,
    );
  }
}
