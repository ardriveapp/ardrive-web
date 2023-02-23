import 'package:ardrive/blocs/upload/models/models.dart';
import 'package:ardrive/blocs/upload/upload_file_checker.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final UploadFileChecker uploadFileChecker = UploadFileChecker(
    privateFileSafeSizeLimit: 100,
    publicFileSafeSizeLimit: 100,
  );

  group('hasFileAboveSafePublicSizeLimit', () {
    late IOFile ioFileAboveSafeLimit;
    late IOFile ioFileUnderSafeLimit;

    setUp(() async {
      ioFileAboveSafeLimit = await IOFile.fromData(
        Uint8List(101), // one byte above the limit
        name: 'test.txt',
        lastModifiedDate: DateTime.now(),
      );
      ioFileUnderSafeLimit = await IOFile.fromData(
        Uint8List(99), // one byte under the limit
        name: 'test.txt',
        lastModifiedDate: DateTime.now(),
      );
    });

    test('should return false if the list of files is empty', () async {
      final result = await uploadFileChecker.hasFileAboveSafePublicSizeLimit(
        files: [],
      );

      expect(result, false);
    });
    test('should return false if no files are above the limit', () async {
      final result = await uploadFileChecker.hasFileAboveSafePublicSizeLimit(
        files: [
          UploadFile(
            ioFile: ioFileUnderSafeLimit,
            parentFolderId: 'parentFolderId',
          ),
        ],
      );

      expect(result, false);
    });

    test('should return true if a file is above the limit', () async {
      final result = await uploadFileChecker.hasFileAboveSafePublicSizeLimit(
        files: [
          UploadFile(
            ioFile: ioFileAboveSafeLimit,
            parentFolderId: 'parentFolderId',
          ),
          UploadFile(
            ioFile: ioFileUnderSafeLimit,
            parentFolderId: 'parentFolderId',
          ),
        ],
      );

      expect(result, true);
    });
    test('should return true when all files are above limit', () async {
      final result = await uploadFileChecker.hasFileAboveSafePublicSizeLimit(
        files: [
          UploadFile(
            ioFile: ioFileAboveSafeLimit,
            parentFolderId: 'parentFolderId',
          ),
          UploadFile(
            ioFile: ioFileAboveSafeLimit,
            parentFolderId: 'parentFolderId',
          ),
          UploadFile(
            ioFile: ioFileAboveSafeLimit,
            parentFolderId: 'parentFolderId',
          ),
        ],
      );

      expect(result, true);
    });
  });

  group('checkAndReturnFilesAbovePrivateLimit', () {
    late IOFile ioFileAboveSafeLimit;
    late IOFile ioFileUnderSafeLimit;

    setUp(() async {
      ioFileAboveSafeLimit = await IOFile.fromData(
        Uint8List(101), // one byte above the limit
        name: 'test.txt',
        lastModifiedDate: DateTime.now(),
      );
      ioFileUnderSafeLimit = await IOFile.fromData(
        Uint8List(99), // one byte under the limit
        name: 'test.txt',
        lastModifiedDate: DateTime.now(),
      );
    });

    test('should return empty list if no files are above the limit', () async {
      final result =
          await uploadFileChecker.checkAndReturnFilesAbovePrivateLimit(
        files: [
          UploadFile(
            ioFile: ioFileUnderSafeLimit,
            parentFolderId: 'parentFolderId',
          ),
        ],
      );

      expect(result, []);
    });

    // test empry list
    test('should return list of files above the limit', () async {
      final result =
          await uploadFileChecker.checkAndReturnFilesAbovePrivateLimit(
        files: [
          UploadFile(
            ioFile: ioFileAboveSafeLimit,
            parentFolderId: 'parentFolderId',
          ),
          UploadFile(
            ioFile: ioFileUnderSafeLimit,
            parentFolderId: 'parentFolderId',
          ),
        ],
      );

      expect(result, [ioFileAboveSafeLimit.path]);
    });

    test('should return list of all files above the limit', () async {
      final result =
          await uploadFileChecker.checkAndReturnFilesAbovePrivateLimit(
        files: [
          UploadFile(
            ioFile: ioFileAboveSafeLimit,
            parentFolderId: 'parentFolderId',
          ),
          UploadFile(
            ioFile: ioFileAboveSafeLimit,
            parentFolderId: 'parentFolderId',
          ),
          UploadFile(
            ioFile: ioFileAboveSafeLimit,
            parentFolderId: 'parentFolderId',
          ),
        ],
      );

      expect(result, [
        ioFileAboveSafeLimit.path,
        ioFileAboveSafeLimit.path,
        ioFileAboveSafeLimit.path,
      ]);
    });

    test('should return empty list if the list of files is empty', () async {
      final result =
          await uploadFileChecker.checkAndReturnFilesAbovePrivateLimit(
        files: [],
      );

      expect(result, []);
    });
  });
}
