import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockUploadController extends Mock implements UploadController {}

class _MockIOFile extends Mock implements IOFile {}

class _MockMetadata extends Mock implements ARFSFileUploadMetadata {}

UploadInProgress _inProgress(UploadMethod method) => UploadInProgress(
      progress: UploadProgress.notStarted(),
      totalProgress: 0,
      controller: _MockUploadController(),
      uploadMethod: method,
    );

FileUploadTask _task(UploadType type) => FileUploadTask(
      file: _MockIOFile(),
      metadata: _MockMetadata(),
      type: type,
      uploadThumbnail: false,
    );

void main() {
  group('isWalletPaidUploadAtRisk', () {
    test('an upload paid from the wallet is at risk while it runs', () {
      expect(isWalletPaidUploadAtRisk(_inProgress(UploadMethod.ar)), isTrue);
    });

    test('an upload paid with Turbo credits is not', () {
      expect(
          isWalletPaidUploadAtRisk(_inProgress(UploadMethod.turbo)), isFalse);
    });

    test('failed wallet-paid files are at risk until they are re-uploaded', () {
      expect(
        isWalletPaidUploadAtRisk(UploadFailure(
          error: UploadErrors.unknown,
          failedTasks: [_task(UploadType.turbo), _task(UploadType.d2n)],
        )),
        isTrue,
      );
    });

    test('failed Turbo files, or a failure with no files, are not', () {
      expect(
        isWalletPaidUploadAtRisk(UploadFailure(
          error: UploadErrors.unknown,
          failedTasks: [_task(UploadType.turbo)],
        )),
        isFalse,
      );
      expect(
        isWalletPaidUploadAtRisk(UploadFailure(error: UploadErrors.unknown)),
        isFalse,
      );
    });

    test('a finished upload is not', () {
      expect(isWalletPaidUploadAtRisk(UploadComplete()), isFalse);
    });
  });
}
