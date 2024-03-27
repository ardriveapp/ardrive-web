import 'dart:async';

import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A form widget that manages the validation of child text fields.
class ArDriveForm extends StatefulWidget {
  /// The child widget of the form.
  final Widget child;

  /// Creates an instance of [ArDriveForm].
  ///
  /// The [child] argument must not be null.
  const ArDriveForm({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  State<ArDriveForm> createState() => ArDriveFormState();
}

class ArDriveFormState extends State<ArDriveForm> {
  bool _isValid = true;
  final List<ArDriveTextFieldState> _textFields = [];

  @override
  void didChangeDependencies() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.visitChildElements((element) {
        _findTextFields(element);
      });
    });

    super.didChangeDependencies();
  }

  @override
  void initState() {
    super.initState();
  }

  /// Validates the form asynchronously.
  ///
  /// This method triggers the validation of all text fields in the form.
  /// If any field is invalid, the form is considered invalid.
  ///
  /// Returns a [Future] that completes with `true` if the form is valid,
  /// otherwise completes with `false`.
  Future<bool> validate() async {
    _isValid = true;

    await _waitValidations();

    return _isValid;
  }

  Future<void> _waitValidations() async {
    context.visitChildElements((element) async {
      if (element is! ArDriveTextField) {
        return await _findAndValidateTextFieldAsync(element);
      }
    });
  }

  Future<void> _findAndValidateTextFieldAsync(Element e) async {
    e.visitChildElements((element) async {
      if (element.widget is! ArDriveTextField) {
        return _findAndValidateTextFieldAsync(element);
      }

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        _isValid = _isValid &&
            await ((element as StatefulElement).state as ArDriveTextFieldState)
                .validateAsync();
      });
    });
  }

  /// Validates the form synchronously.
  ///
  /// This method triggers the synchronous validation of all text fields in the form.
  /// If any field is invalid, the form is considered invalid.
  ///
  /// Returns `true` if the form is valid, otherwise returns `false`.
  bool validateSync({void Function(bool)? callback}) {
    _isValid = true;

    _findAndValidateTextFieldSync();

    return _isValid;
  }

  void _findAndValidateTextFieldSync() {
    for (var i = 0; i < _textFields.length; i++) {
      _isValid = _isValid && _textFields[i].validateSync();
    }
  }

  void _findTextFields(Element e) {
    e.visitChildElements((element) {
      if (element.widget is! ArDriveTextField) {
        return _findTextFields(element);
      }

      if (_textFields.contains(
          ((element as StatefulElement).state as ArDriveTextFieldState))) {
        return;
      }

      _textFields.add(((element).state as ArDriveTextFieldState));
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class ArDriveMultlineObscureTextController extends TextEditingController {
  bool _isObscured = true;
  bool _showLastCharacter = false;
  Timer? _timer;

  ArDriveMultlineObscureTextController({String? text}) : super(text: text);

  // use same default obscuring character as EditableText
  final obscuringCharacter = '\u2022';

  @override
  TextSpan buildTextSpan(
      {required BuildContext context,
      TextStyle? style,
      required bool withComposing}) {
    return _isObscured
        ? TextSpan(
            style: style,
            text: _showLastCharacter
                ? text
                    .replaceAll(RegExp(r'.'), obscuringCharacter)
                    .replaceRange(
                        text.length - 1, text.length, text[text.length - 1])
                : text.replaceAll(RegExp(r'.'), obscuringCharacter))
        : super.buildTextSpan(
            context: context, style: style, withComposing: withComposing);
  }

  @override
  set value(TextEditingValue newValue) {
    var oldText = super.text;
    var newText = newValue.text;

    if (_isObscured && newText.length == oldText.length + 1) {
      _showLastCharacter = true;
      _timer?.cancel();
      _timer = Timer(const Duration(seconds: 1), () {
        _showLastCharacter = false;
        _timer = null;
        notifyListeners();
      });
    }
    super.value = newValue;
  }

  bool get isObscured => _isObscured;
  set isObscured(bool newValue) {
    _isObscured = newValue;
    _showLastCharacter = false;
    _timer?.cancel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class ArDriveTextField extends StatefulWidget {
  const ArDriveTextField({
    super.key,
    this.isEnabled = true,
    this.asyncValidator,
    this.hintText,
    this.onChanged,
    this.obscureText = false,
    this.autofillHints,
    this.autovalidateMode = AutovalidateMode.disabled,
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
    this.showObfuscationToggle = false,
    this.textInputAction = TextInputAction.done,
    this.suffixIcon,
    this.textStyle,
    this.useErrorMessageOffset = false,
    this.preffix,
    this.showErrorMessage = true,
    this.validator,
    this.minLines = 1,
    this.maxLines = 1,
    this.errorMessage,
  });

  final bool isEnabled;
  final FutureOr<String?>? Function(String?)? asyncValidator;
  final String? Function(String?)? validator;
  final Function(String)? onChanged;
  final String? hintText;
  final bool obscureText;
  final List<String>? autofillHints;
  final AutovalidateMode? autovalidateMode;
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
  final bool showObfuscationToggle;
  final TextInputAction textInputAction;
  final Widget? suffixIcon;
  final TextStyle? textStyle;
  final bool useErrorMessageOffset;
  final Widget? preffix;
  final bool showErrorMessage;
  final int? minLines;
  final int? maxLines;
  final String? errorMessage;

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
    _isObscureText = widget.obscureText;
    if (widget.maxLines != null && widget.maxLines! > 1) {
      assert(widget.controller is ArDriveMultlineObscureTextController);
    }
    super.initState();
  }

  late bool _isObscureText;

  String? _errorMessage;
  String? _currentText;

  @override
  Widget build(BuildContext context) {
    final theme = ArDriveTheme.of(context).themeData.textFieldTheme;
    final controller = widget.controller;
    final isMultline = (controller is ArDriveMultlineObscureTextController);
    final obscureText = isMultline ? false : _isObscureText;

    if (isMultline) {
      (controller).isObscured = _isObscureText;
    }

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
                child: _textFieldLabel(widget.label!, theme),
              ),
            ),
          TextFormField(
            controller: controller,
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
            textInputAction: widget.textInputAction,
            obscureText: obscureText,
            style: widget.textStyle ?? theme.inputTextStyle,
            autovalidateMode: widget.autovalidateMode,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
            onChanged: (text) {
              if (widget.asyncValidator != null) {
                widget.asyncValidator!(text);
                validateAsync(text: text);
              } else if (widget.validator != null) {
                widget.validator!(text);
                validateSync(text: text);
              }

              widget.onChanged?.call(text);
              _currentText = text;
            },
            autofillHints: widget.autofillHints,
            enabled: widget.isEnabled,
            decoration: InputDecoration(
              prefix: widget.preffix,
              suffix: widget.suffixIcon ??
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isObscureText = !_isObscureText;
                      });
                    },
                    child: ArDriveClickArea(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: widget.showObfuscationToggle
                            ? ArDriveIcon(
                                icon: _isObscureText
                                    ? ArDriveIconsData.eye_closed
                                    : ArDriveIconsData.eye_open,
                                color: theme.inputTextColor,
                              )
                            : null,
                      ),
                    ),
                  ),
              errorStyle: const TextStyle(height: 0),
              hintText: widget.hintText,
              hintStyle: ArDriveTypography.body
                  .inputLargeRegular(color: _hintTextColor(theme)),
              enabledBorder: _getEnabledBorder(theme),
              focusedBorder: _getFocusedBoder(theme),
              disabledBorder: _getDisabledBorder(theme),
              filled: true,
              fillColor: theme.inputBackgroundColor,
              contentPadding: theme.contentPadding,
            ),
          ),
          if (widget.showErrorMessage &&
              widget.asyncValidator != null &&
              widget.asyncValidator is Future)
            FutureBuilder(
              future: widget.asyncValidator?.call(_currentText) as Future,
              builder: (context, snapshot) {
                return _errorMessageLabel(theme);
              },
            ),
          if (widget.showErrorMessage &&
              (widget.validator != null || widget.errorMessage != null))
            _errorMessageLabel(theme),
          if (widget.successMessage != null)
            _successMessage(widget.successMessage!, theme),
        ],
      ),
    );
  }

  Widget _errorMessageLabel(ArDriveTextFieldTheme theme) {
    final err = widget.errorMessage ?? _errorMessage;
    return AnimatedTextFieldLabel(
      text: err,
      showing: err != null,
      style: ArDriveTypography.body.bodyBold(
        color: theme.errorColor,
      ),
      useLabelOffset: widget.useErrorMessageOffset,
    );
  }

  Widget _textFieldLabel(String message, ArDriveTextFieldTheme theme) {
    return Row(
      children: [
        TextFieldLabel(
          text: message,
          style: ArDriveTypography.body.buttonNormalBold(
            color: widget.isFieldRequired
                ? theme.requiredLabelColor
                : theme.labelColor,
          ),
        ),
        if (widget.isFieldRequired)
          Text(
            ' *',
            style: ArDriveTypography.body.buttonNormalRegular(
              color: theme.labelColor,
            ),
          )
      ],
    );
  }

  Widget _successMessage(String message, ArDriveTextFieldTheme theme) {
    return AnimatedTextFieldLabel(
      text: message,
      showing: textFieldState == TextFieldState.success,
      style: ArDriveTypography.body.bodyRegular(
        color: theme.successColor,
      ),
    );
  }

  InputBorder _getBorder(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: BorderSide(color: color, width: 2),
    );
  }

  InputBorder _getEnabledBorder(ArDriveTextFieldTheme theme) {
    if (textFieldState == TextFieldState.success) {
      return _getSuccessBorder(theme);
    } else if (textFieldState == TextFieldState.error) {
      return _getErrorBorder(theme);
    }
    return _getBorder(theme.defaultBorderColor);
  }

  InputBorder _getFocusedBoder(ArDriveTextFieldTheme theme) {
    if (textFieldState == TextFieldState.success) {
      return _getSuccessBorder(theme);
    } else if (textFieldState == TextFieldState.error) {
      return _getErrorBorder(theme);
    }

    return _getBorder(
      ArDriveTheme.of(context).themeData.colors.themeFgDefault,
    );
  }

  InputBorder _getDisabledBorder(ArDriveTextFieldTheme theme) {
    return _getBorder(theme.inputDisabledBorderColor);
  }

  InputBorder _getErrorBorder(ArDriveTextFieldTheme theme) {
    return _getBorder(theme.errorBorderColor);
  }

  InputBorder _getSuccessBorder(ArDriveTextFieldTheme theme) {
    return _getBorder(theme.successBorderColor);
  }

  Color _hintTextColor(ArDriveTextFieldTheme theme) {
    if (widget.isEnabled) {
      return theme.inputPlaceholderColor;
    }
    return theme.disabledTextColor;
  }

  FutureOr<bool> validateAsync({String? text}) async {
    String? textToValidate = text;

    if (textToValidate == null && widget.controller != null) {
      textToValidate = widget.controller?.text;
    }

    final validation = await widget.asyncValidator?.call(textToValidate);

    setState(() {
      if (textToValidate?.isEmpty ?? true) {
        textFieldState = TextFieldState.focused;
      } else if (validation != null) {
        textFieldState = TextFieldState.error;
      } else if (validation == null) {
        textFieldState = TextFieldState.success;
      }
    });

    _errorMessage = validation;

    return validation == null;
  }

  bool validateSync({String? text}) {
    String? textToValidate = text;

    if (textToValidate == null && widget.controller != null) {
      textToValidate = widget.controller?.text;
    }

    final validation = widget.validator?.call(textToValidate);

    setState(() {
      if (textToValidate?.isEmpty ?? true) {
        textFieldState = TextFieldState.focused;
      } else if (validation != null) {
        textFieldState = TextFieldState.error;
      } else if (validation == null) {
        textFieldState = TextFieldState.success;
      }
    });

    _errorMessage = validation;

    return validation == null;
  }
}

@visibleForTesting
class AnimatedTextFieldLabel extends StatefulWidget {
  const AnimatedTextFieldLabel({
    super.key,
    required this.text,
    required this.showing,
    required this.style,
    this.useLabelOffset = false,
  });

  final String? text;
  final bool showing;
  final TextStyle style;
  final bool useLabelOffset;

  @override
  State<AnimatedTextFieldLabel> createState() => AnimatedTextFieldLabelState();
}

class AnimatedTextFieldLabelState extends State<AnimatedTextFieldLabel> {
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (Widget child, Animation<double> animation) {
            final inAnimation = Tween<Offset>(
                    begin: const Offset(0.0, -1.0), end: const Offset(0.0, 0.0))
                .animate(animation);
            final outAnimation = Tween<Offset>(
                    begin: const Offset(0.0, 0.0), end: const Offset(0.0, 1.0))
                .animate(animation);

            return ClipRect(
              child: SlideTransition(
                position: child.key == const ValueKey(true)
                    ? inAnimation
                    : outAnimation,
                child: FadeTransition(
                  opacity: animation,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: child,
                  ),
                ),
              ),
            );
          },
          child: widget.showing
              ? SizedBox(
                  height: 22,
                  key: const ValueKey(true),
                  child: TextFieldLabel(
                    style: widget.style,
                    text: widget.text ?? '',
                  ),
                )
              : Container(
                  key: const ValueKey(false),
                  height: widget.useLabelOffset ? 22 : 0,
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
