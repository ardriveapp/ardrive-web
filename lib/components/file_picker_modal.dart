import 'package:app_settings/app_settings.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_io/ardrive_io.dart';
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
        return SizedBox(
          height: 240,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ListTile(
                  onTap: () async {
                    try {
                      content = await pickFromCamera();
                    } catch (e) {
                      if (e is FileSystemPermissionDeniedException) {
                        await _showCameraPermissionModal(context);
                      }
                    }
                    Navigator.pop(context);
                  },
                  title: Text(appLocalizationsOf(context).camera),
                  leading: const Icon(Icons.camera),
                ),
                const SizedBox(
                  height: 8,
                ),
                ListTile(
                  onTap: () async {
                    content = await pickFromGallery();
                    Navigator.pop(context);
                  },
                  title: Text(appLocalizationsOf(context).gallery),
                  leading: const Icon(Icons.image),
                ),
                const SizedBox(
                  height: 8,
                ),
                ListTile(
                    onTap: () async {
                      content = await pickFromFileSystem();

                      Navigator.pop(context);
                    },
                    title: Text(appLocalizationsOf(context).fileSystem),
                    leading: const Icon(Icons.file_open_sharp))
              ],
            ),
          ),
        );
      });
  return content;
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
