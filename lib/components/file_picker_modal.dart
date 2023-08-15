import 'package:app_settings/app_settings.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

import 'app_dialog.dart';

Future<List<IOFile>> showMultipleFilesFilePickerModal(
  BuildContext context,
) {
  final io = ArDriveIO();
  return _showModal<List<IOFile>>(
      context,
      () => io.pickFiles(fileSource: FileSource.fileSystem),
      () => io.pickFiles(fileSource: FileSource.gallery),
      () async => [await (io.pickFile(fileSource: FileSource.camera))]);
}

Future<IOFile> showFilePickerModal(BuildContext context) async {
  final io = ArDriveIO();
  return _showModal<IOFile>(
      context,
      () => io.pickFile(fileSource: FileSource.fileSystem),
      () => io.pickFile(fileSource: FileSource.gallery),
      () => io.pickFile(fileSource: FileSource.camera));
}

Future<T> _showModal<T>(
  BuildContext context,
  Future<T> Function() pickFromFileSystem,
  Future<T> Function() pickFromGallery,
  Future<T> Function() pickFromCamera,
) async {
  late T content;

  await showModalBottomSheet(
      context: context,
      builder: (context) {
        return _FilePickerContent<T>(
          pickFromCamera: pickFromCamera,
          pickFromFileSystem: pickFromFileSystem,
          pickFromGallery: pickFromGallery,
          onClose: (c) async {
            content = c;
          },
        );
      });
  return content;
}

class _FilePickerContent<T> extends StatefulWidget {
  const _FilePickerContent({
    super.key,
    required this.onClose,
    required this.pickFromCamera,
    required this.pickFromFileSystem,
    required this.pickFromGallery,
  });
  final Function(T) onClose;
  final Future<T> Function() pickFromFileSystem;
  final Future<T> Function() pickFromGallery;
  final Future<T> Function() pickFromCamera;

  @override
  State<_FilePickerContent<T>> createState() => __FilePickerContentState<T>();
}

class __FilePickerContentState<T> extends State<_FilePickerContent<T>> {
  bool _isLoading = false;
  @override
  Widget build(BuildContext context) {
    final textStyle = ArDriveTypography.body.buttonLargeRegular(
      color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
    );
    return Container(
      color: ArDriveTheme.of(context).themeData.tableTheme.backgroundColor,
      height: 240,
      child: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  Padding(
                    padding: EdgeInsets.only(top: 16.0),
                    child: Text('Preparing your file(s)...'),
                  ),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ListTile(
                    onTap: () async {
                      setState(() {
                        _isLoading = true;
                      });

                      try {
                        final content = await widget.pickFromCamera();

                        widget.onClose(content);
                      } catch (e) {
                        if (e is FileSystemPermissionDeniedException) {
                          await _showCameraPermissionModal(context);
                          logger.d(e.toString());
                        }
                      }

                      setState(() {
                        _isLoading = false;
                      });

                      // ignore: use_build_context_synchronously
                      Navigator.pop(context);
                    },
                    title: Text(
                      appLocalizationsOf(context).camera,
                      style: textStyle,
                    ),
                    leading: ArDriveIcons.camera1(),
                  ),
                  const Divider(
                    height: 8,
                  ),
                  ListTile(
                    onTap: () async {
                      setState(() {
                        _isLoading = true;
                      });
                      try {
                        final isEnabled =
                            await verifyStoragePermissionAndShowModalWhenDenied(
                          context,
                        );

                        if (isEnabled) {
                          final content = await widget.pickFromGallery();

                          widget.onClose(content);

                          logger.d('adding file');
                        }
                      } catch (e) {
                        logger.e(e.toString());
                      }

                      setState(() {
                        _isLoading = false;
                      });

                      // ignore: use_build_context_synchronously
                      Navigator.pop(context);
                    },
                    title: Text(
                      appLocalizationsOf(context).gallery,
                      style: textStyle,
                    ),
                    leading: ArDriveIcons.image(),
                  ),
                  const Divider(
                    height: 8,
                  ),
                  ListTile(
                    onTap: () async {
                      setState(() {
                        _isLoading = true;
                      });
                      try {
                        final isEnabled =
                            await verifyStoragePermissionAndShowModalWhenDenied(
                          context,
                        );

                        if (isEnabled) {
                          final content = await widget.pickFromFileSystem();

                          widget.onClose(content);

                          logger.d('adding file');
                        }
                      } catch (e) {
                        logger.e(e.toString());
                      }

                      setState(() {
                        _isLoading = false;
                      });

                      // ignore: use_build_context_synchronously
                      Navigator.pop(context);
                    },
                    title: Text(
                      appLocalizationsOf(context).fileSystem,
                      style: textStyle,
                    ),
                    leading: ArDriveIcons.fileOutlined(),
                  )
                ],
              ),
            ),
    );
  }
}

Future<bool> verifyStoragePermissionAndShowModalWhenDenied(
    BuildContext context) async {
  try {
    await verifyStoragePermission();
  } catch (e) {
    if (e is FileSystemPermissionDeniedException) {
      await showStoragePermissionModal(context);
    }
    return false;
  }

  return true;
}

Future<void> showStoragePermissionModal(BuildContext context) async {
  return showDialog(
      context: context,
      builder: (context) {
        return ArDriveStandardModal(
          title: appLocalizationsOf(context).enableStorageAccessTitle,
          description: appLocalizationsOf(context).enableStorageAccess,
          actions: [
            ModalAction(
              action: () {
                Navigator.pop(context);
              },
              title: appLocalizationsOf(context).cancel,
            ),
            ModalAction(
              action: () {
                AppSettings.openAppSettings();
              },
              title: appLocalizationsOf(context).goToDeviceSettings,
            ),
          ],
        );
      });
}

Future<void> _showCameraPermissionModal(BuildContext context) async {
  return showDialog(
      context: context,
      builder: (context) {
        return AppDialog(
          title: appLocalizationsOf(context).enableCamera,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(appLocalizationsOf(context).enableCameraAccess),
              const SizedBox(
                height: 24,
              ),
              ElevatedButton(
                onPressed: () {
                  AppSettings.openAppSettings();
                },
                child: Text(appLocalizationsOf(context).goToDeviceSettings),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: Text(appLocalizationsOf(context).cancel),
              )
            ],
          ),
        );
      });
}
