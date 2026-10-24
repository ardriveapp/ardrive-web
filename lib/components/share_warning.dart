import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// A sentence in a share dialog that must be read before the link is sent: a
/// warning [ArDriveNotice], so the colour carries the severity and the
/// sentence stays in the normal text colour.
class ShareWarning extends StatelessWidget {
  const ShareWarning(
    this.text, {
    super.key,
    this.margin = const EdgeInsets.only(top: 12),
  });

  final String text;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: SizedBox(
        width: double.infinity,
        child: ArDriveNotice(
          type: ArDriveNoticeType.warning,
          message: text,
        ),
      ),
    );
  }
}
