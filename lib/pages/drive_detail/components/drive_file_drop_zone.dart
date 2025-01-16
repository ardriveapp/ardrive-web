import 'dart:ui';

import 'package:ardrive/components/upload_form.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dropzone/flutter_dropzone.dart';

class DriveFileDropZone extends StatefulWidget {
  final String driveId;
  final String folderId;

  const DriveFileDropZone({
    super.key,
    required this.driveId,
    required this.folderId,
  });

  @override
  DriveFileDropZoneState createState() => DriveFileDropZoneState();
}

class DriveFileDropZoneState extends State<DriveFileDropZone> {
  late DropzoneViewController controller;
  bool isHovering = false;
  bool isCurrentlyShown = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
      child: IgnorePointer(
        child: Stack(
          children: [
            BackdropFilter(
              filter: isHovering
                  ? ImageFilter.blur(sigmaX: 2, sigmaY: 2)
                  : ImageFilter.blur(sigmaX: 0.1, sigmaY: 0.1),
              blendMode: BlendMode.srcOver,
              child: ArDriveDropZone(
                  withBorder: false,
                  onDragEntered: () => setState(() => isHovering = true),
                  key: const Key('dropZone'),
                  onDragExited: () => setState(() => isHovering = false),
                  onDragDone: (files) => _onDrop(
                        files,
                        driveId: widget.driveId,
                        parentFolderId: widget.folderId,
                        context: context,
                      ),
                  onError: (e) async {
                    if (e is DropzoneWrongInputException) {
                      await showArDriveDialog(
                        context,
                        content: ArDriveStandardModal(
                          title: appLocalizationsOf(context).error,
                          content: Text(
                            appLocalizationsOf(context).errorDragAndDropFolder,
                          ),
                          actions: [
                            ModalAction(
                              action: () => Navigator.of(context).pop(false),
                              title: appLocalizationsOf(context).ok,
                            ),
                          ],
                        ),
                        barrierDismissible: true,
                      ).then((value) => isCurrentlyShown = false);
                    }

                    return _onLeave();
                  },
                  child: isHovering
                      ? _buildDropZoneOnHover()
                      : const SizedBox.expand()),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onDrop(
    List<IOFile> files, {
    required BuildContext context,
    required String driveId,
    required String parentFolderId,
  }) async {
    if (!isCurrentlyShown) {
      isCurrentlyShown = true;
      _onLeave();

      promptToUpload(
        context,
        driveId: driveId,
        parentFolderId: parentFolderId,
        isFolderUpload: false,
        files: files,
      ).then((value) => isCurrentlyShown = false);
    }
  }

  void _onLeave() => setState(() => isHovering = false);

  Widget _buildDropZoneOnHover() {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Center(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.width,
        decoration: BoxDecoration(
          border: Border.all(
            color: colorTokens.containerL0,
          ),
          color: colorTokens.containerL3,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ArDriveIcons.iconUploadFiles(size: 64),
            const SizedBox(width: 16),
            Text(
              appLocalizationsOf(context).uploadFiles,
              style: typography.heading1(
                fontWeight: ArFontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
