import 'package:ardrive/blocs/upload/models/upload_file.dart';

class UploadFileChecker {
  UploadFileChecker({
    required int publicFileSafeSizeLimit,
    required int privateFileSafeSizeLimit,
  })  : _publicFileSafeSizeLimit = publicFileSafeSizeLimit,
        _privateFileSafeSizeLimit = privateFileSafeSizeLimit;

  final int _publicFileSafeSizeLimit;
  final int _privateFileSafeSizeLimit;

  Future<bool> hasFileAboveSafePublicSizeLimit(
      {required List<UploadFile> files}) async {
    for (final file in files) {
      final fileSize = await file.ioFile.length;
      if (fileSize > _publicFileSafeSizeLimit) {
        return true;
      }
    }
    return false;
  }

  Future<List<String>> checkAndReturnFilesAbovePrivateLimit(
      {required List<UploadFile> files}) async {
    final filesAbovePrivateLimit = <String>[];

    for (final file in files) {
      final fileSize = await file.ioFile.length;
      if (fileSize > _privateFileSafeSizeLimit) {
        filesAbovePrivateLimit.add(file.getIdentifier());
      }
    }

    return filesAbovePrivateLimit;
  }
}
