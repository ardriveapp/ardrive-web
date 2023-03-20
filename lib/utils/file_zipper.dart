import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ardrive_io/ardrive_io.dart';

class FileZipper {
  List<IOFile> files;

  FileZipper({required this.files});

  Future<IOFile> _zipFiles() async {
    // Create a new archive
    final archive = Archive();

    // Add files to the archive
    for (final file in files) {
      final filename = file.name;
      final bytes = await file.readAsBytes();
      archive.addFile(ArchiveFile.noCompress(filename, bytes.length, bytes));
    }

    // Zip the archive
    final zipBytes = ZipEncoder().encode(archive);

    return IOFile.fromData(
      Uint8List.fromList(zipBytes!),
      name: 'files.zip',
      lastModifiedDate: DateTime.now(),
    );
  }

  Future<void> downloadZipFile() async {
    final zipBytes = await _zipFiles();

    ArDriveIO().saveFile(zipBytes);
  }
}
