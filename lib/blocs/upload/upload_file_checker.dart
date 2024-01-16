import 'package:ardrive/blocs/upload/models/upload_file.dart';

class UploadFileSizeChecker {
  UploadFileSizeChecker({
    required int fileSizeLimit,
    required int fileSizeWarning,
  })  : _fileSizeLimit = fileSizeLimit,
        _fileSizeWarning = fileSizeWarning;

  final int _fileSizeLimit;
  final int _fileSizeWarning;

  Future<bool> hasFileAboveSizeLimit({
    required List<UploadFile> files,
  }) =>
      _hasFileAboveLimit(files: files, limit: _fileSizeLimit);

  Future<bool> hasFileAboveWarningSizeLimit({
    required List<UploadFile> files,
  }) =>
      _hasFileAboveLimit(files: files, limit: _fileSizeWarning);

  Future<List<String>> getFilesAboveSizeLimit({
    required List<UploadFile> files,
  }) async {
    final filesAboveSizeLimit = <String>[];

    for (final file in files) {
      final fileSize = await file.ioFile.length;
      if (fileSize > _fileSizeLimit) {
        filesAboveSizeLimit.add(file.getIdentifier());
      }
    }

    return filesAboveSizeLimit;
  }

  Future<bool> _hasFileAboveLimit({
    required List<UploadFile> files,
    required int limit,
  }) async {
    for (final file in files) {
      final fileSize = await file.ioFile.length;
      if (fileSize > limit) {
        return true;
      }
    }

    return false;
  }
}
