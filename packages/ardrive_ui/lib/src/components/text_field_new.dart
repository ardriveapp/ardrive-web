import 'dart:async';

import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A form widget that manages the validation of child text fields.
class ArDriveFormNew extends StatefulWidget {
  /// The child widget of the form.
  final Widget child;

  /// Creates an instance of [ArDriveFormNew].
  ///
  /// The [child] argument must not be null.
  const ArDriveFormNew({
    super.key,
    required this.child,
  });

  @override
  State<ArDriveFormNew> createState() => ArDriveFormNewState();
}

class ArDriveFormNewState extends State<ArDriveFormNew> {
  bool _isValid = true;
  final List<ArDriveTextFieldStateNew> _textFields = [];

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
      if (element is! ArDriveTextFieldNew) {
        return await _findAndValidateTextFieldAsync(element);
      }
    });
  }

  Future<void> _findAndValidateTextFieldAsync(Element e) async {
    e.visitChildElements((element) async {
      if (element.widget is! ArDriveTextFieldNew) {
        return _findAndValidateTextFieldAsync(element);
      }

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        _isValid = _isValid &&
            await ((element as StatefulElement).state
                    as ArDriveTextFieldStateNew)
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
      if (element.widget is! ArDriveTextFieldNew) {
        return _findTextFields(element);
      }

      if (_textFields.contains(
          ((element as StatefulElement).state as ArDriveTextFieldStateNew))) {
        return;
      }

      _textFields.add(((element).state as ArDriveTextFieldStateNew));
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class ArDriveMultilineObscureTextControllerNew extends TextEditingController {
  bool _isObscured = true;
  bool _showLastCharacter = false;
  Timer? _timer;

  ArDriveMultilineObscureTextControllerNew({super.text});

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
            text: text.isEmpty
                ? ''
                : _showLastCharacter
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

class ArDriveTextFieldNew extends StatefulWidget {
  const ArDriveTextFieldNew({
    super.key,
    this.isEnabled = true,
    this.asyncValidator,
    this.hintText,
    this.hintStyle,
    this.onChanged,
    this.obscureText = false,
    this.autofillHints,
    this.autovalidateMode = AutovalidateMode.disabled,
    this.successMessage,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.autofocus = false,
    this.controller,
    this.initialValue,
    this.inputFormatters,
    this.keyboardType,
    this.onTap,
    this.onFieldSubmitted,
    this.onEditingComplete,
    this.focusNode,
    this.maxLength,
    this.label,
    this.isFieldRequired = false,
    this.showObfuscationToggle = false,
    this.textInputAction = TextInputAction.done,
    this.suffixIcon,
    this.textStyle,
    this.useErrorMessageOffset = false,
    this.prefix,
    this.showErrorMessage = true,
    this.validator,
    this.minLines = 1,
    this.maxLines = 1,
    this.errorMessage,
    this.prefixIcon,
    this.onTapOutside,
  });

  final bool isEnabled;
  final FutureOr<String?>? Function(String?)? asyncValidator;
  final String? Function(String?)? validator;
  final Function(String)? onChanged;
  final String? hintText;
  final TextStyle? hintStyle;
  final bool obscureText;
  final List<String>? autofillHints;
  final AutovalidateMode? autovalidateMode;
  final String? successMessage;
  final bool autocorrect;

  /// Whether the keyboard offers word suggestions. Off for a secret that
  /// isn't a password, such as a recovery phrase.
  final bool enableSuggestions;
  final bool autofocus;
  final String? initialValue;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final Function()? onTap;
  final Function(String)? onFieldSubmitted;

  /// Called when the reader finishes editing, before [onFieldSubmitted]. When
  /// set, finishing no longer takes focus from the field, which a field that
  /// acts on Enter and stays open for more typing needs.
  final VoidCallback? onEditingComplete;
  final int? maxLength;
  final FocusNode? focusNode;
  final String? label;
  final bool isFieldRequired;
  final bool showObfuscationToggle;
  final TextInputAction textInputAction;
  final Widget? suffixIcon;
  final TextStyle? textStyle;
  final bool useErrorMessageOffset;
  final Widget? prefix;
  final bool showErrorMessage;
  final int? minLines;
  final int? maxLines;
  final String? errorMessage;
  final Widget? prefixIcon;
  final Function(PointerDownEvent)? onTapOutside;

  @override
  State<ArDriveTextFieldNew> createState() => ArDriveTextFieldStateNew();
}

enum TextFieldStateNew { unfocused, focused, disabled, error, success }

@visibleForTesting
class ArDriveTextFieldStateNew extends State<ArDriveTextFieldNew> {
  @visibleForTesting
  late TextFieldStateNew textFieldState;

  @override
  void initState() {
    textFieldState = TextFieldStateNew.unfocused;
    _isObscureText = widget.obscureText;
    // Only an obscured field needs the multiline controller: Flutter's own
    // obscured field is one line. A plain multiline field, such as a
    // description, failed this in debug builds.
    if (widget.obscureText && widget.maxLines != null && widget.maxLines! > 1) {
      assert(widget.controller is ArDriveMultilineObscureTextControllerNew);
    }
    super.initState();
  }

  late bool _isObscureText;

  @override
  void didUpdateWidget(covariant ArDriveTextFieldNew oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A parent that hides or shows the text itself (one eye for a password
    // and its confirmation, say) is followed.
    if (oldWidget.obscureText != widget.obscureText) {
      _isObscureText = widget.obscureText;
    }
  }

  String? _errorMessage;
  String? _currentText;

  static Widget? _withGap(Widget? suffix) => suffix == null
      ? null
      : Padding(
          padding: const EdgeInsets.only(left: ArDriveSpacing.xs),
          child: suffix,
        );

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    final controller = widget.controller;
    final isMultline = (controller is ArDriveMultilineObscureTextControllerNew);
    final obscureText = isMultline ? false : _isObscureText;

    // An ID or a key passes a code() style as [textStyle] for its face. It
    // takes the field's colour for its enabled state unless it names one,
    // and its line stays the height of the field's own, so the field is the
    // same height as the others in the form whatever size the text is.
    //
    // Not merged over the field's style: the field's style names the
    // package its face comes from, and a merge prefixed the passed family
    // with it, naming a face that isn't registered.
    final baseStyle = typography.paragraphNormal(
      color: widget.isEnabled ? colorTokens.textMid : colorTokens.textXLow,
      fontWeight: ArFontWeight.semiBold,
    );
    final textStyle = widget.textStyle;
    final fieldStyle = textStyle == null
        ? baseStyle
        : textStyle.copyWith(
            color: textStyle.color ?? baseStyle.color,
            height: baseStyle.fontSize! *
                baseStyle.height! /
                (textStyle.fontSize ?? baseStyle.fontSize!),
          );

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
                child: _textFieldLabel(widget.label!, colorTokens, typography),
              ),
            ),
          TextFormField(
            onTapOutside: widget.onTapOutside,
            controller: controller,
            autocorrect: widget.autocorrect,
            enableSuggestions: widget.enableSuggestions,
            autofocus: widget.autofocus,
            initialValue: widget.initialValue,
            keyboardType: widget.keyboardType,
            inputFormatters: widget.inputFormatters,
            onTap: widget.onTap,
            onFieldSubmitted: widget.onFieldSubmitted,
            onEditingComplete: widget.onEditingComplete,
            maxLength: widget.maxLength,
            focusNode: widget.focusNode,
            key: widget.key,
            textInputAction: widget.textInputAction,
            obscureText: obscureText,
            style: fieldStyle,
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
              prefix: widget.prefix,
              prefixIcon: widget.prefixIcon,
              // A gap before the suffix, so the end of a long value and its
              // caret don't run into it: an eye sat flush on the last letter.
              suffix: _withGap(widget.showObfuscationToggle
                  ? GestureDetector(
                      onTap: () {
                        setState(() {
                          _isObscureText = !_isObscureText;
                        });
                      },
                      child: ArDriveClickArea(
                        child: Container(
                          child: widget.showObfuscationToggle
                              ? ArDriveIcon(
                                  size: 20,
                                  icon: _isObscureText
                                      ? ArDriveIconsData.eye_closed
                                      : ArDriveIconsData.eye_open,
                                  color: _isObscureText
                                      ? colorTokens.iconLow
                                      : colorTokens.iconMid)
                              : null,
                        ),
                      ),
                    )
                  : widget.suffixIcon),
              errorStyle: const TextStyle(height: 0),
              hintText: widget.hintText,
              hintStyle: widget.hintStyle ??
                  typography.paragraphNormal(
                      color: colorTokens.textXLow,
                      fontWeight: ArFontWeight.semiBold),
              enabledBorder: _getEnabledBorder(colorTokens),
              focusedBorder: _getFocusedBoder(colorTokens),
              disabledBorder: _getDisabledBorder(colorTokens),
              filled: true,
              fillColor: widget.isEnabled
                  ? colorTokens.inputDefault
                  : colorTokens.inputDisabled,
              contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            ),
          ),
          if (widget.showErrorMessage &&
              widget.asyncValidator != null &&
              widget.asyncValidator is Future)
            FutureBuilder(
              future: widget.asyncValidator?.call(_currentText) as Future,
              builder: (context, snapshot) {
                return _errorMessageLabel(colorTokens, typography);
              },
            ),
          if (widget.showErrorMessage &&
              (widget.validator != null || widget.errorMessage != null))
            _errorMessageLabel(colorTokens, typography),
          if (widget.successMessage != null)
            _successMessage(widget.successMessage!, colorTokens, typography),
        ],
      ),
    );
  }

  Widget _errorMessageLabel(
      ArDriveColorTokens colorTokens, ArdriveTypographyNew typography) {
    final err = widget.errorMessage ?? _errorMessage;
    // Read out when it appears, so a screen reader hears "Wrong password"
    // and every other field error without hunting for it.
    return Semantics(
      liveRegion: true,
      child: AnimatedTextFieldLabelNew(
        text: err,
        showing: err != null,
        // The error text colour, not the red of the field's edge: that one is
        // for a border and measures under 3:1 as text.
        style: typography.paragraphNormal(
          color: colorTokens.statusErrorFg,
          fontWeight: ArFontWeight.semiBold,
        ),
        useLabelOffset: widget.useErrorMessageOffset,
      ),
    );
  }

  Widget _textFieldLabel(String message, ArDriveColorTokens colorTokens,
      ArdriveTypographyNew typography) {
    return Row(
      children: [
        // Flexible, so a label longer than the field (a narrow dialog, a
        // long translation) wraps instead of overflowing.
        Flexible(
          child: TextFieldLabelNew(
            text: message,
            style: typography.paragraphNormal(
              // color: widget.isFieldRequired
              //     ? theme.requiredLabelColor
              //     : theme.labelColor,
              color: colorTokens.textLow,
              fontWeight: ArFontWeight.semiBold,
            ),
          ),
        ),
        if (widget.isFieldRequired)
          Text(
            ' *',
            style: typography.paragraphNormal(
              color: colorTokens.textLow,
            ),
          )
      ],
    );
  }

  Widget _successMessage(String message, ArDriveColorTokens colorTokens,
      ArdriveTypographyNew typography) {
    return AnimatedTextFieldLabelNew(
      text: message,
      showing: textFieldState == TextFieldStateNew.success,
      style: typography.paragraphNormal(
        color: colorTokens.textMid,
        fontWeight: ArFontWeight.semiBold,
      ),
    );
  }

  InputBorder _getBorder(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(ArDriveRadius.control),
      borderSide: BorderSide(color: color, width: 1),
    );
  }

  InputBorder _getEnabledBorder(ArDriveColorTokens colorTokens) {
    // FIXME: Ask about success border
    // if (textFieldState == TextFieldState.success) {
    //   return _getSuccessBorder(colorTokens);
    // } else
    // An error handed in from outside (a server's rejection) gets the same
    // edge as one the validator found.
    if (textFieldState == TextFieldStateNew.error ||
        widget.errorMessage != null) {
      return _getErrorBorder(colorTokens);
    }
    return _getBorder(colorTokens.strokeMid);
  }

  InputBorder _getFocusedBoder(ArDriveColorTokens colorTokens) {
    // if (textFieldState == TextFieldState.success) {
    //   return _getSuccessBorder(colorTokens);
    // } else
    // An error handed in from outside (a server's rejection) gets the same
    // edge as one the validator found.
    if (textFieldState == TextFieldStateNew.error ||
        widget.errorMessage != null) {
      return _getErrorBorder(colorTokens);
    }

    return _getBorder(colorTokens.strokeHigh);
  }

  InputBorder _getDisabledBorder(ArDriveColorTokens colorTokens) {
    return _getBorder(colorTokens.strokeMid);
  }

  InputBorder _getErrorBorder(ArDriveColorTokens colorTokens) {
    return _getBorder(colorTokens.strokeRed);
  }

  // InputBorder _getSuccessBorder(ArDriveColorTokens colorTokens) {
  //   // return _getBorder(theme.successBorderColor);

  // }

  // Color _hintTextColor(ArDriveColorTokens colorTokens) {
  //   return colorTokens.textXLow;
  // }

  FutureOr<bool> validateAsync({String? text}) async {
    String? textToValidate = text;

    if (textToValidate == null && widget.controller != null) {
      textToValidate = widget.controller?.text;
    }

    final validation = await widget.asyncValidator?.call(textToValidate);

    setState(() {
      if (textToValidate?.isEmpty ?? true) {
        textFieldState = TextFieldStateNew.focused;
      } else if (validation != null) {
        textFieldState = TextFieldStateNew.error;
      } else if (validation == null) {
        textFieldState = TextFieldStateNew.success;
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
        textFieldState = TextFieldStateNew.focused;
      } else if (validation != null) {
        textFieldState = TextFieldStateNew.error;
      } else if (validation == null) {
        textFieldState = TextFieldStateNew.success;
      }
    });

    _errorMessage = validation;

    return validation == null;
  }
}

@visibleForTesting
class AnimatedTextFieldLabelNew extends StatefulWidget {
  const AnimatedTextFieldLabelNew({
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
  State<AnimatedTextFieldLabelNew> createState() =>
      AnimatedTextFieldLabelNewState();
}

class AnimatedTextFieldLabelNewState extends State<AnimatedTextFieldLabelNew> {
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
                  child: TextFieldLabelNew(
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

class TextFieldLabelNew extends StatelessWidget {
  const TextFieldLabelNew({
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
