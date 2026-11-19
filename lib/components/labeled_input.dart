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
        // A field's label, as every field draws it (the design system's
        // text fields): it used to be 16 px in text-mid, bigger than the
        // labels of the fields beside it.
        Text(
          labelText,
          style: ArDriveTypographyNew.of(context).paragraphNormal(
            color: ArDriveTheme.of(context).themeData.colorTokens.textLow,
            fontWeight: ArFontWeight.semiBold,
          ),
        ),
        const SizedBox(height: ArDriveSpacing.xs),
        child,
      ],
    );
  }
}
