import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';

enum RadioButtonState { unchecked, hover, checked, disabled }

class RadioButtonOptions {
  RadioButtonOptions({
    this.value = false,
    this.isEnabled = true,
    required this.text,
  });

  bool value;
  bool isEnabled;
  String text;
}

class ArDriveRadioButtonGroup extends StatefulWidget {
  const ArDriveRadioButtonGroup({
    super.key,
    required this.options,
    this.onChanged,
    this.alignment = Alignment.centerLeft,
  });

  final List<RadioButtonOptions> options;
  final Function(int, bool)? onChanged;
  final Alignment alignment;

  @override
  State<ArDriveRadioButtonGroup> createState() =>
      _ArDriveRadioButtonGroupState();
}

class _ArDriveRadioButtonGroupState extends State<ArDriveRadioButtonGroup> {
  late final List<ValueNotifier<RadioButtonOptions>> _options;

  @override
  void initState() {
    _options = List.generate(
        widget.options.length,
        (i) => ValueNotifier(
              RadioButtonOptions(
                isEnabled: widget.options[i].isEnabled,
                value: widget.options[i].value,
                text: widget.options[i].text,
              ),
            ));

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemBuilder: (context, i) {
        return Align(
          alignment: widget.alignment,
          child: ValueListenableBuilder(
            builder: (context, t, w) {
              return ArDriveRadioButton(
                value: _options[i].value.value,
                text: _options[i].value.text,
                onChange: (value) async {
                  for (int j = 0; j < _options.length; j++) {
                    if (j == i) {
                      continue;
                    }
                    if (_options[j].value.value) {
                      _options[j].value.value = false;
                    }
                  }
                  _options[i].value.value = value;

                  widget.onChanged?.call(i, value);
                },
              );
            },
            valueListenable: _options[i],
          ),
        );
      },
      itemCount: _options.length,
      shrinkWrap: true,
    );
  }
}

class ArDriveRadioButton extends StatefulWidget {
  const ArDriveRadioButton({
    super.key,
    this.value = false,
    this.isEnabled = true,
    required this.text,
    this.onChange,
  });

  final bool value;
  final bool isEnabled;
  final String text;
  final Function(bool)? onChange;

  @override
  State<ArDriveRadioButton> createState() => ArDriveRadioButtonState();
}

@visibleForTesting
class ArDriveRadioButtonState extends State<ArDriveRadioButton> {
  @visibleForTesting
  late RadioButtonState state;
  late bool _value;

  @override
  void initState() {
    _verifyState();
    super.initState();
  }

  @override
  void didUpdateWidget(covariant ArDriveRadioButton oldWidget) {
    _verifyState();
    setState(() {});
    super.didUpdateWidget(oldWidget);
  }

  void _verifyState() {
    if (!widget.isEnabled) {
      state = RadioButtonState.disabled;
      _value = false;
    } else if (widget.value) {
      state = RadioButtonState.checked;
      _value = true;
    } else {
      state = RadioButtonState.unchecked;
      _value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _radio();
  }

  Widget _radio() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: GestureDetector(
            onTap: () async {
              if (state == RadioButtonState.disabled) {
                return;
              }
              if (state == RadioButtonState.unchecked) {
                setState(() {
                  state = RadioButtonState.checked;
                });
              } else if (state == RadioButtonState.checked) {
                setState(() {
                  state = RadioButtonState.unchecked;
                });
              }

              _value = !_value;

              widget.onChange?.call(_value);
            },
            child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 24,
                width: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _color(),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: state == RadioButtonState.checked ||
                            (state == RadioButtonState.disabled && widget.value)
                        ? 10
                        : 0,
                    width: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _color(),
                    ),
                  ),
                )),
          ),
        ),
        const SizedBox(
          width: 8,
        ),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Text(
              widget.text,
              style: ArDriveTypography.body.bodyRegular(),
            ),
          ),
        )
      ],
    );
  }

  Color _color() {
    switch (state) {
      case RadioButtonState.unchecked:
        return ArDriveTheme.of(context).themeData.colors.themeAccentDefault;
      case RadioButtonState.hover:
        return ArDriveTheme.of(context).themeData.colors.themeFgDefault;
      case RadioButtonState.checked:
        return ArDriveTheme.of(context).themeData.colors.themeFgDefault;
      case RadioButtonState.disabled:
        return ArDriveTheme.of(context).themeData.colors.themeFgDisabled;
    }
  }
}
