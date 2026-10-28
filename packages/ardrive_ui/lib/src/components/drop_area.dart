import 'dart:async';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:dotted_border/dotted_border.dart';
// ignore: depend_on_referenced_packages
import 'package:file_selector/file_selector.dart';
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
    this.withBorder = true,
  });

  final Widget child;
  final Function(List<IOFile> files)? onDragDone;
  final Function()? onDragEntered;
  final Function()? onDragExited;
  final Function(Object e)? onError;
  final bool withBorder;

  @override
  State<ArDriveDropZone> createState() => _ArDriveDropZoneState();
}

class _ArDriveDropZoneState extends State<ArDriveDropZone> {
  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragDone: (detail) async {
        try {
          final files = await Future.wait(detail.files.map((e) async {
            if (await verifyIfFolder(e)) {
              throw DropzoneWrongInputException();
            }

            // Convert XFile to IOFile with proper MIME type detection
            final ioFile = await IOFileAdapter().fromXFile(e);

            // If the content type is the generic octet-stream,
            // try to detect it from the file extension
            if (ioFile.contentType == 'application/octet-stream') {
              // Use the existing lookupMimeTypeWithDefaultType from ardrive_io
              final detectedMimeType =
                  lookupMimeTypeWithDefaultType(ioFile.name);

              if (detectedMimeType != 'application/octet-stream') {
                // Create a new IOFile with the correct content type
                final bytes = await ioFile.readAsBytes();
                return IOFileAdapter().fromData(
                  bytes,
                  name: ioFile.name,
                  contentType: detectedMimeType,
                  lastModifiedDate: ioFile.lastModifiedDate,
                );
              }
            }

            return ioFile;
          }));

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
      child: widget.withBorder ? _borderedChild() : widget.child,
    );
  }

  Widget _borderedChild() {
    return DottedBorder(
      borderType: BorderType.RRect,
      radius: const Radius.circular(8),
      color: ArDriveTheme.of(context).themeData.colorTokens.textMid,
      child: widget.child,
    );
  }

  // A folder is not a valid input
  Future<bool> verifyIfFolder(XFile file) async {
    try {
      await file.openRead(0, 1).listen((event) {}).asFuture();
    } catch (e) {
      return true;
    }

    return false;
  }
}

/// Returns one file using the drop area or the button
///
class DropzoneValidationException implements Exception {}

class DropzoneWrongInputException implements Exception {}
