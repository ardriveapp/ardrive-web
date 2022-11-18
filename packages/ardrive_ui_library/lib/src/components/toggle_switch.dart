import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/framework.dart';

class ArDriveToggleSwitch extends StatefulWidget {
  const ArDriveToggleSwitch({
    super.key,
    required this.text,
    this.onChanged,
    this.value = false,
    this.isEnabled = true,
  });

  final String text;
  final bool value;
  final bool isEnabled;
  final Function(bool value)? onChanged;

  @override
  State<ArDriveToggleSwitch> createState() => _ArDriveToggleSwitchState();
}

class _ArDriveToggleSwitchState extends State<ArDriveToggleSwitch> {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: ArDriveToggle(
            initialValue: widget.value,
            isEnabled: widget.isEnabled,
            onChanged: widget.onChanged,
          ),
        ),
        const SizedBox(
          width: 8,
        ),
        Text(
          widget.text,
          style: ArDriveTypography.body.bodyRegular(),
        ),
      ],
    );
  }
}
