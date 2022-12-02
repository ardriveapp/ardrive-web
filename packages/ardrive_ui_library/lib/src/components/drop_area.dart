import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:ardrive_ui_library/src/constants/size_constants.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';

/// `onDragDone` pass a list of `IOFile` dropped on the area under the `child` widget.
///
/// `onError` returns the exception thrown by the `ArdriveIO` in case of any errors
class ArDriveDropZone extends StatefulWidget {
  const ArDriveDropZone({
    super.key,
    required this.child,
    this.onDragDone,
    this.onDragEntered,
    this.onDragExited,
    this.onError,
  });

  final Widget child;
  final Function(List<IOFile> files)? onDragDone;
  final Function()? onDragEntered;
  final Function()? onDragExited;
  final Function(Object e)? onError;

  @override
  State<ArDriveDropZone> createState() => _ArDriveDropZoneState();
}

class _ArDriveDropZoneState extends State<ArDriveDropZone> {
  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragDone: (detail) async {
        try {
          final files = await Future.wait(
              detail.files.map((e) => IOFileAdapter().fromXFile(e)));
          widget.onDragDone?.call(files);
        } catch (e) {
          widget.onError?.call(e);
        }
      },
      onDragEntered: (detail) {
        widget.onDragEntered?.call();
      },
      onDragExited: (detail) {
        widget.onDragExited?.call();
      },
      child: DottedBorder(
        strokeWidth: 1,
        strokeCap: StrokeCap.butt,
        color: ArDriveTheme.of(context).themeData.colors.themeFgMuted,
        child: widget.child,
      ),
    );
  }
}

/// Returns one file using the drop area or the button
///
class ArDriveDropAreaSingleInput extends StatefulWidget {
  const ArDriveDropAreaSingleInput({
    super.key,
    this.height,
    this.width,
    required this.dragAndDropDescription,
    required this.dragAndDropButtonTitle,
    this.buttonCallback,
    this.onDragDone,
    this.onDragEntered,
    this.onDragExited,
    this.errorDescription,
    this.onError,
  });

  final double? height;
  final double? width;
  final String dragAndDropDescription;
  final String dragAndDropButtonTitle;
  final String? errorDescription;
  final Function()? onDragEntered;
  final Function()? onDragExited;
  final Function(IOFile file)? buttonCallback;
  final Function(IOFile file)? onDragDone;
  final Function(Object e)? onError;

  @override
  State<ArDriveDropAreaSingleInput> createState() =>
      _ArDriveDropAreaSingleInputState();
}

class _ArDriveDropAreaSingleInputState
    extends State<ArDriveDropAreaSingleInput> {
  bool _hasError = false;
  Color? _backgroundColor;
  IOFile? _file;

  @override
  Widget build(BuildContext context) {
    return ArDriveDropZone(
      onDragEntered: () {
        widget.onDragEntered?.call();
      },
      onDragDone: (files) {
        setState(() {
          _file = files.first;
          widget.onDragDone?.call(_file!);
        });
      },
      onError: (e) {
        setState(() {
          _hasError = true;
          _backgroundColor =
              ArDriveTheme.of(context).themeData.colors.themeErrorMuted;
        });
        widget.onError?.call(e);
      },
      onDragExited: () {
        widget.onDragExited?.call();
      },
      child: Container(
        color: _backgroundColor,
        height: widget.height,
        width: widget.width,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: _hasError
              ? _errorView()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _file != null
                        ? ArDriveIcons.checkSuccess(
                            size: dropAreaIconSize,
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeFgMuted,
                          )
                        : ArDriveIcons.uploadCloud(
                            size: dropAreaIconSize,
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
                        onPressed: () async {
                          _file = await ArDriveIO()
                              .pickFile(fileSource: FileSource.fileSystem);
                          setState(() {});
                          widget.buttonCallback?.call(_file!);
                        },
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
    );
  }

  Widget _errorView() {
    return Column(
      children: [
        ArDriveIcons.warning(),
        const SizedBox(
          height: 8,
        ),
        if (widget.errorDescription != null)
          Text(
            widget.errorDescription!,
            style: ArDriveTypography.body.smallBold(),
          ),
      ],
    );
  }
}
