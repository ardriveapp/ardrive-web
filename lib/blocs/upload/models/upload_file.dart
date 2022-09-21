import 'package:ardrive_io/ardrive_io.dart';

class UploadFile {
  const UploadFile({
    required this.ioFile,
    required this.parentFolderId,
    this.relativeTo,
  });

  final String? relativeTo;
  final IOFile ioFile;

  // This MF is supposed to hold the EID of its parent
  final String parentFolderId;

  String getIdentifier() {
    print('File path at UploadFile: ${ioFile.path}');
    print('relativeTo at UploadFile: $relativeTo');
    return ioFile.path.isEmpty || _isPathBlobFromDragAndDrop(ioFile.path)
        ? ioFile.name
        : (relativeTo != null
            ? ioFile.path.replaceFirst('$relativeTo/', '')
            : ioFile.path);
  }

  bool _isPathBlobFromDragAndDrop(String path) {
    return path.split(':')[0] == 'blob';
  }
}
