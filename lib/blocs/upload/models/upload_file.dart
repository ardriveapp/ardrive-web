import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive_io/ardrive_io.dart';

class UploadFile {
  UploadFile({
    required this.ioFile,
    required this.parentFolderId,
    this.relativeTo,
  }) {
    logger.d(
      'Instantiating UploadFile. filePath: ${ioFile.path},'
      ' fileName: ${ioFile.name},'
      ' parentFolderId: $parentFolderId,'
      ' relativeTo: $relativeTo',
    );
  }

  final String? relativeTo;
  final IOFile ioFile;
  final String parentFolderId;

  String getIdentifier() {
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
