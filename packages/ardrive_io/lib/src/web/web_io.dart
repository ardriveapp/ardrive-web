import 'dart:async';
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_io/src/utils/completer.dart';
import 'package:ardrive_io/src/utils/print_utils.dart';
import 'package:ardrive_io/src/web/stream_saver.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:file_system_access_api/file_system_access_api.dart';
import 'package:flutter/foundation.dart';

/// Web implementation to use `ArDriveIO` API
///
class WebIO implements ArDriveIO {
  WebIO({
    required FileProviderFactory fileProviderFactory,
  }) : _fileProviderFactory = fileProviderFactory;

  final FileProviderFactory _fileProviderFactory;

  @override
  Future<IOFile> pickFile({
    List<String>? allowedExtensions,
    FileSource fileSource = FileSource.fileSystem,
  }) async {
    final provider =
        _fileProviderFactory.fromSource(fileSource) as MultiFileProvider;

    return provider.pickFile(fileSource: fileSource);
  }

  @override
  Future<List<IOFile>> pickFiles({
    List<String>? allowedExtensions,
    FileSource fileSource = FileSource.fileSystem,
  }) async {
    final provider =
        _fileProviderFactory.fromSource(fileSource) as MultiFileProvider;

    return provider.pickMultipleFiles(fileSource: fileSource);
  }

  @override
  Future<IOFolder> pickFolder() async {
    final provider = _fileProviderFactory.fromSource(FileSource.fileSystem)
        as MultiFileProvider;

    return provider.getFolder();
  }

  @override
  Future<void> saveFile(IOFile file) async {
    final savePath = await file_selector.getSaveLocation();

    if (savePath == null) {
      throw EntityPathException();
    }

    file_selector.XFile.fromData(
      await file.readAsBytes(),
      lastModified: file.lastModifiedDate,
      mimeType: file.contentType,
      name: file.name,
    ).saveTo(savePath.path);
  }

  @override
  Stream<SaveStatus> saveFileStream(
      IOFile file, Completer<bool> finalize) async* {
    if (FileSystemAccess.supported) {
      ardriveIODebugPrint('Saving using FileSystemAccess API');
      yield* _saveFileSystemAccessApi(file, finalize);
    } else {
      ardriveIODebugPrint('Saving using StreamSaver.js');
      yield* _saveFileStreamSaver(file, finalize);
    }
  }

  Stream<SaveStatus> _saveFileSystemAccessApi(
      IOFile file, Completer<bool> finalize) async* {
    var bytesSaved = 0;
    final totalBytes = await file.length;
    yield SaveStatus(
      bytesSaved: bytesSaved,
      totalBytes: totalBytes,
    );

    try {
      final extension =
          getFileExtension(name: file.name, contentType: file.contentType);

      final handle = await window.showSaveFilePicker(
          suggestedName: file.name,
          excludeAcceptAllOption: true,
          types: [
            FilePickerAcceptType(
              description: file.contentType,
              accept: {
                file.contentType: [extension]
              },
            ),
          ],
          startIn: WellKnownDirectory.downloads);

      final writable = await handle.createWritable();
      final writer = writable.getWriter();

      await for (final chunk in file.openReadStream()) {
        if (await completerMaybe(finalize) == false) {
          ardriveIODebugPrint('Cancelling saveFileStream...');
          break;
        }

        await writer.ready;
        await writer.write(chunk);

        ardriveIODebugPrint('Wrote ${chunk.length} bytes to file');

        bytesSaved += chunk.length;

        ardriveIODebugPrint('Bytes saved: $bytesSaved');

        yield SaveStatus(
          bytesSaved: bytesSaved,
          totalBytes: totalBytes,
        );
      }

      ardriveIODebugPrint('Finished writing to file');

      ardriveIODebugPrint('Closing file...');
      writer.releaseLock();
      await writable.close();
      finalize.complete(true);

      ardriveIODebugPrint('Finalizing saveFileStream...');

      final finalizeResult = await finalize.future;
      if (!finalizeResult) {
        ardriveIODebugPrint('Cancelling saveFileStream...');
        await handle.remove();
      }

      ardriveIODebugPrint('SaveFileStream finalized');

      yield SaveStatus(
        bytesSaved: bytesSaved,
        totalBytes: totalBytes,
        saveResult: finalizeResult,
      );

      ardriveIODebugPrint('SaveFileStream yielded');
    } on AbortError {
      // User dismissed dialog or picked a file deemed too sensitive or dangerous.
      ardriveIODebugPrint(
          'User dismissed dialog or picked a file deemed too sensitive or dangerous.');
      throw ActionCanceledException();
    } on NotAllowedError {
      // User did not granted permission to readwrite in this file.
      throw FileReadWritePermissionDeniedException();
    } on Exception {
      ardriveIODebugPrint(
          '[ardrive_io]: failed to save file using FileSystemAccess API');
      yield SaveStatus(
        bytesSaved: bytesSaved,
        totalBytes: totalBytes,
        saveResult: false,
      );
    }
  }

  Stream<SaveStatus> _saveFileStreamSaver(
      IOFile file, Completer<bool> finalize) async* {
    var bytesSaved = 0;

    final totalBytes = await file.length;

    yield SaveStatus(
      bytesSaved: bytesSaved,
      totalBytes: totalBytes,
    );

    try {
      final writable = createWriteStream(file.name, {
        'size': await file.length,
      });

      final writer = writable.getWriter();

      await for (final chunk in file.openReadStream()) {
        if (await completerMaybe(finalize) == false) break;
        await writer.readyFuture;
        await writer.writeFuture(chunk);

        bytesSaved += chunk.length;
        yield SaveStatus(
          bytesSaved: bytesSaved,
          totalBytes: totalBytes,
        );
      }

      await writer.readyFuture;

      ardriveIODebugPrint('writer ready');

      finalize.complete(true);

      final finalizeResult = await finalize.future;

      if (!finalizeResult) {
        ardriveIODebugPrint('Cancelling saveFileStream...');
        writer.abort();
        await writable.abortFuture('Finalize result is false');
      } else {
        await writer.closeFuture();
        writer.close();
        writer.releaseLock();
      }

      yield SaveStatus(
        bytesSaved: bytesSaved,
        totalBytes: totalBytes,
        saveResult: true,
      );
    } on Exception {
      yield SaveStatus(
        bytesSaved: bytesSaved,
        totalBytes: totalBytes,
        saveResult: false,
      );
    }
  }
}

class WebFileSystemProvider implements MultiFileProvider {
  WebFileSystemProvider(
    this._folderPicker,
    this._ioFileAdapter,
    this._ioFolderAdapter,
  );

  final FolderPicker _folderPicker;
  final IOFileAdapter _ioFileAdapter;
  final IOFolderAdapter _ioFolderAdapter;

  @override
  Future<IOFolder> getFolder() async {
    final files = <IOFile>[];

    late Stream<List<IOFile>> folderStream;

    _folderPicker.pickFolderFiles((stream) => folderStream = stream);

    await for (var file in folderStream) {
      files.addAll(file);
    }

    return _ioFolderAdapter.fromIOFiles(files);
  }

  Future<IOFile> _platformFileToStreamFile(PlatformFile platformFile) {
    return _ioFileAdapter.fromReadStreamGenerator(
      platformFile.readStream!,
      platformFile.size,
      name: platformFile.name,
      lastModifiedDate: platformFile.lastModified ?? DateTime.now(),
      contentType: lookupMimeTypeWithDefaultType(platformFile.extension ?? ''),
    );
  }

  @override
  Future<IOFile> pickFile({
    List<String>? allowedExtensions,
    required FileSource fileSource,
  }) async {
    final pickerResult = await FilePicker.platform.pickFiles(
      allowedExtensions: allowedExtensions,
      allowMultiple: false,
      withReadStream: true,
      withData: false,
    );

    if (pickerResult == null || pickerResult.files.length != 1) {
      throw ActionCanceledException();
    }

    return _platformFileToStreamFile(pickerResult.files.first);
  }

  @override
  Future<List<IOFile>> pickMultipleFiles({
    List<String>? allowedExtensions,
    required FileSource fileSource,
  }) async {
    final pickerResult = await FilePicker.platform.pickFiles(
      allowedExtensions: allowedExtensions,
      allowMultiple: true,
      withReadStream: true,
      withData: false,
    );

    if (pickerResult == null || pickerResult.files.isEmpty) {
      throw ActionCanceledException();
    }

    return Future.wait(
        pickerResult.files.map(_platformFileToStreamFile).toList());
  }
}

/// Pass a stream to the `getFiles` callback to stream files
/// When the file picker window is closed it will return a list of `IOFile`
class FolderPicker {
  Future<void> pickFolderFiles(
      Function(Stream<List<IOFile>> stream) getFiles) async {
    StreamController<List<IOFile>> folderController =
        StreamController<List<IOFile>>();

    /// Set the stream to get the files
    getFiles(folderController.stream);

    final folderInput = FileUploadInputElement();

    folderInput.setAttribute('webkitdirectory', true);

    folderInput.click();

    folderInput.onChange.listen((e) async {
      // read file content as dataURL
      final files = folderInput.files;

      if (files == null) {
        throw ActionCanceledException();
      }

      /// To avoid the `IOFileAdapter` imports dart:html, this file will be mounted
      /// here.
      folderController.add(files.map((e) => _mountFile(e)).toList());

      /// Closes to finish the stream with all files
      folderController.close();
      folderInput.removeAttribute('webkitdirectory');
      folderInput.remove();
    });
  }

  WebFile _mountFile(File e) {
    final path = e.relativePath;
    if (path == null) {
      throw EntityPathException();
    }

    /// Needs on safari. Some files doesn't have the lastModified and an exception
    /// is thrown
    DateTime lastModifiedDate;
    try {
      lastModifiedDate = e.lastModifiedDate;
    } catch (e) {
      lastModifiedDate = DateTime.now();
    }

    return WebFile(e,
        name: e.name,
        lastModifiedDate: lastModifiedDate,
        path: path,
        contentType: lookupMimeTypeWithDefaultType(path));
  }
}

class WebFile implements IOFile {
  WebFile(
    File file, {
    required this.name,
    required this.lastModifiedDate,
    required this.path,
    required this.contentType,
  }) : _file = file;

  final File _file;

  Uint8List? _bytes;

  @override
  String name;

  @override
  DateTime lastModifiedDate;

  @override
  String path;

  @override
  final String contentType;

  @override
  Future<Uint8List> readAsBytes() async {
    final bytes = _bytes;
    if (bytes == null) {
      final reader = FileReader();
      reader.readAsArrayBuffer(_file);
      await reader.onLoad.first;
      return reader.result as Uint8List;
    }

    return bytes;
  }

  @override
  Future<String> readAsString() async {
    return utf8.decode(await readAsBytes());
  }

  @override
  Stream<Uint8List> openReadStream([int start = 0, int? end]) async* {
    if (_bytes != null) {
      yield _bytes!.sublist(start, end ?? _bytes!.length);
      return;
    }

    final reader = FileReader();

    int globalOffset = start;
    int globalEnd = end ?? _file.size;
    while (globalOffset < globalEnd) {
      final chunkEnd = globalOffset + readStreamChunkSize > globalEnd
          ? globalEnd
          : globalOffset + readStreamChunkSize;

      final blob = _file.slice(globalOffset, chunkEnd);
      reader.readAsArrayBuffer(blob);
      await reader.onLoad.first;

      yield reader.result as Uint8List;

      globalOffset += readStreamChunkSize;
    }
  }

  @override
  FutureOr<int> get length async => _bytes?.length ?? _file.size;

  @override
  String toString() {
    return 'file name: $name\nfile path: $path\nlast modified date: ${lastModifiedDate.toIso8601String()}\nlength: $length';
  }
}
