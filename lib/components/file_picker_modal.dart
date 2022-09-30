import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:flutter/material.dart';

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
    return SizedBox(
      height: 240,
      child: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  CircularProgressIndicator(),
                  Padding(
                    padding: EdgeInsets.only(top: 16.0),
                    child: Text('Preparing your file...'),
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
                      } catch (e) {}

                      setState(() {
                        _isLoading = false;
                      });

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
                      setState(() {
                        _isLoading = true;
                      });
                      try {
                        final content = await widget.pickFromGallery();

                        widget.onClose(content);
                      } catch (e) {}

                      setState(() {
                        _isLoading = false;
                      });
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
                        setState(() {
                          _isLoading = true;
                        });
                        try {
                          final content = await widget.pickFromFileSystem();

                          widget.onClose(content);
                        } catch (e) {}

                        setState(() {
                          _isLoading = false;
                        });
                        Navigator.pop(context);
                      },
                      title: Text(appLocalizationsOf(context).fileSystem),
                      leading: const Icon(Icons.file_open_sharp))
                ],
              ),
            ),
    );
  }
}
