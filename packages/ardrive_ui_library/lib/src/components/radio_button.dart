import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

enum RadioButtonState { normal, hover, checked, disabled }

class RadioButtonOptions {
  RadioButtonOptions({
    this.value = false,
    this.isEnabled = true,
    required this.text,
    this.index,
  });

  bool value;
  bool isEnabled;
  String text;
  int? index;
}

class ArDriveRadioButtonGroup extends StatefulWidget {
  const ArDriveRadioButtonGroup({
    super.key,
    required this.options,
    this.onChanged,
  });

  final List<RadioButtonOptions> options;
  final Function(int, bool)? onChanged;

  @override
  State<ArDriveRadioButtonGroup> createState() =>
      _ArDriveRadioButtonGroupState();
}

class _ArDriveRadioButtonGroupState extends State<ArDriveRadioButtonGroup> {
  late List<RadioButtonOptions> _options;

  @override
  void initState() {
    _options = List.generate(
      widget.options.length,
      (i) => RadioButtonOptions(
        index: i,
        isEnabled: widget.options[i].isEnabled,
        value: widget.options[i].value,
        text: widget.options[i].text,
      ),
    );
    _keys = List.generate(_options.length, (index) => const Uuid().v1());

    super.initState();
  }

  late List _keys;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemBuilder: (context, i) {
        return ArDriveRadioButton(
          key: ValueKey(_keys[i]),
          text: _options[i].text,
          onChange: (value) async {
            for (int j = 0; j < _options.length; j++) {
              if (j == i) {
                continue;
              }
              if (_options[j].value) {
                _options[j].value = false;
                _keys[j] = const Uuid().v1();
              }
            }
            setState(() {});

            _options[i].value = value;
            widget.onChanged?.call(i, value);
          },
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
  State<ArDriveRadioButton> createState() => _ArDriveRadioButtonState();
}

class _ArDriveRadioButtonState extends State<ArDriveRadioButton> {
  late RadioButtonState _state;
  late bool _value;

  @override
  void initState() {
    if (!widget.isEnabled) {
      _state = RadioButtonState.disabled;
      _value = false;
    } else if (widget.value) {
      _state = RadioButtonState.checked;
      _value = true;
    } else {
      _state = RadioButtonState.normal;
      _value = false;
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return _radio();
  }

  Widget _radio() {
    return Row(
      key: widget.key,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: GestureDetector(
            onTap: () async {
              if (_state == RadioButtonState.disabled) {
                return;
              }
              if (_state == RadioButtonState.normal) {
                setState(() {
                  _state = RadioButtonState.checked;
                });
              } else if (_state == RadioButtonState.checked) {
                setState(() {
                  _state = RadioButtonState.normal;
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
                    height: _state == RadioButtonState.checked ||
                            (_state == RadioButtonState.disabled &&
                                widget.value)
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
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Text(
            widget.text,
            style: ArDriveTypography.body.bodyRegular(),
          ),
        )
      ],
    );
  }

  Color _color() {
    switch (_state) {
      case RadioButtonState.normal:
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
