import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_io/src/file_provider.dart';
import 'package:flutter/material.dart';

Future<List<IOFile>> showMultipleFilesFilePickerModal(
  BuildContext context,
) {
  final io = ArDriveIO();
  return _showModal<List<IOFile>>(
      context,
      () => io.pickFiles(fileSource: FileSource.fileSystem),
      () => io.pickFiles(fileSource: FileSource.gallery));
}

Future<IOFile> showFilePickerModal(BuildContext context) async {
  final io = ArDriveIO();
  return _showModal<IOFile>(
      context,
      () => io.pickFile(fileSource: FileSource.fileSystem),
      () => io.pickFile(fileSource: FileSource.gallery));
}

Future<T> _showModal<T>(
  BuildContext context,
  Future<T> Function() pickFromFileSystem,
  Future<T> Function() pickFromGallery,
) async {
  late T content;

  await showModalBottomSheet(
      context: context,
      builder: (context) {
        return SizedBox(
          height: 200,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                const SizedBox(
                  height: 8,
                ),
                ListTile(
                  onTap: () async {
                    content = await pickFromGallery();
                    Navigator.pop(context);
                  },
                  title: const Text('Gallery'),
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
                    title: const Text('Files'),
                    leading: const Icon(Icons.file_open_sharp))
              ],
            ),
          ),
        );
      });
  return content;
}
