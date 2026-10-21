import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/widgets.dart';

class LabeledInput extends StatelessWidget {
  final String labelText;
  final Widget child;

  const LabeledInput({
    super.key,
    required this.labelText,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labelText,
          // Not the disabled colour it was drawn in, which was too faint to
          // read against the dialog.
          style: ArDriveTheme.of(context)
              .themeData
              .textFieldTheme
              .inputTextStyle
              .copyWith(
                color: ArDriveTheme.of(context).themeData.colorTokens.textMid,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}
