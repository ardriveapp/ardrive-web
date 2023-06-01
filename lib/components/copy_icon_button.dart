import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CopyIconButton extends StatelessWidget {
  final String value;
  final double? size;
  final Function? onTap;
  final String? tooltip;

  const CopyIconButton({
    Key? key,
    required this.value,
    this.size,
    this.tooltip,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ArDriveIconButton(
      icon: ArDriveIcons.copy(
        color: Colors.black54,
        size: size,
      ),
      tooltip: tooltip ?? appLocalizationsOf(context).copyTooltip,
      onPressed: () {
        Clipboard.setData(ClipboardData(text: value));
        onTap?.call();
      },
    );
  }
}
