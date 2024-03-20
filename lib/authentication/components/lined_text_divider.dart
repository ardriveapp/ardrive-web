import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class LinedTextDivider extends StatelessWidget {
  final String text;

  const LinedTextDivider({Key? key, this.text = 'or'}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    // FIXME: add switching of typography based on screen size
    final typography = ArDriveTypographyNew.of(context);

    return Row(children: [
      Expanded(
          child: Container(
        decoration: ShapeDecoration(
          shape: RoundedRectangleBorder(
            side: BorderSide(
              width: 0.50,
              strokeAlign: BorderSide.strokeAlignCenter,
              color: colorTokens.strokeLow,
            ),
          ),
        ),
      )),
      Padding(
          padding: const EdgeInsets.only(left: 44, right: 44),
          child: Text(text,
              textAlign: TextAlign.center,
              style: typography.paragraphLarge(
                  color: colorTokens.textLow,
                  fontWeight: ArFontWeight.semiBold))),
      Expanded(
          child: Container(
        decoration: ShapeDecoration(
          shape: RoundedRectangleBorder(
            side: BorderSide(
              width: 0.50,
              strokeAlign: BorderSide.strokeAlignCenter,
              color: colorTokens.strokeLow,
            ),
          ),
        ),
      )),
    ]);
  }
}
