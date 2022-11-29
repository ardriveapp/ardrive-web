import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:ardrive_ui_library/src/constants/size_constants.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';

class ArDriveDropZone extends StatefulWidget {
  const ArDriveDropZone({
    super.key,
    required this.child,
    this.onDragDone,
    this.onDragEntered,
    this.onDragExited,
  });

  final Widget child;
  final Function(IOFile file)? onDragDone;
  final Function()? onDragEntered;
  final Function()? onDragExited;

  @override
  State<ArDriveDropZone> createState() => _ArDriveDropZoneState();
}

class _ArDriveDropZoneState extends State<ArDriveDropZone> {
  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragDone: (detail) async {
        final file = await IOFileAdapter().fromXFile(detail.files.first);
        widget.onDragDone?.call(file);
      },
      onDragEntered: (detail) {
        widget.onDragEntered?.call();
      },
      onDragExited: (detail) {
        widget.onDragExited?.call();
      },
      child: widget.child,
    );
  }
}

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
  IOFile? _file;

  @override
  Widget build(BuildContext context) {
    return ArDriveDropZone(
      onDragEntered: () {},
      onDragDone: (file) {
        setState(() {
          _file = file;
        });
      },
      onDragExited: () {},
      child: DottedBorder(
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
                _file != null
                    ? ArDriveIcons.checkSuccess(
                        size: 56,
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgMuted,
                      )
                    : ArDriveIcons.uploadCloud(
                        size: 56,
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgMuted,
                      ),
                if (_file != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, bottom: 20),
                    child: Text(
                      _file!.name,
                      style: ArDriveTypography.body.smallBold(),
                    ),
                  ),
                if (_file == null) ...[
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
                    backgroundColor: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeFgDefault,
                  ),
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }
}
