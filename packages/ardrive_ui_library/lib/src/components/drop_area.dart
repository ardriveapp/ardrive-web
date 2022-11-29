import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:ardrive_ui_library/src/constants/size_constants.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';



class ArDriveDropArea extends StatefulWidget {
  const ArDriveDropArea({
    super.key,
    this.height,
    this.width,
    required this.dragAndDropDescription,
    required this.dragAndDropButtonTitle,
  });

  final double? height;
  final double? width;
  final String dragAndDropDescription;
  final String dragAndDropButtonTitle;

  @override
  State<ArDriveDropArea> createState() => _ArDriveDropAreaState();
}

class _ArDriveDropAreaState extends State<ArDriveDropArea> {
  @override
  Widget build(BuildContext context) {
    return DottedBorder(
      strokeWidth: 1,
      strokeCap: StrokeCap.butt,
      color: ArDriveTheme.of(context).themeData.colors.themeGbMuted,
      child: SizedBox(
        height: widget.height,
        width: widget.width,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ArDriveIcons.uploadCloud(
                size: 56,
                color: ArDriveTheme.of(context).themeData.colors.themeFgMuted,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 20),
                child: Text(
                  widget.dragAndDropDescription,
                  style: ArDriveTypography.body.smallBold(),
                ),
              ),
              ArDriveButton(
                text: widget.dragAndDropButtonTitle,
                onPressed: () {},
                maxHeight: buttonActionHeight,
                fontStyle: ArDriveTypography.body.buttonNormalRegular(
                  color: ArDriveTheme.of(context)
                      .themeData
                      .colors
                      .themeAccentSubtle,
                ),
                backgroundColor:
                    ArDriveTheme.of(context).themeData.colors.themeFgDefault,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
