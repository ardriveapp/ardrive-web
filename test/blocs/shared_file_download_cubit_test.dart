import 'dart:async';

import 'package:ardrive/blocs/file_download/file_download_cubit.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/download/ardrive_downloader.dart';
import 'package:ardrive/download/download_policy.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_utils/mocks.dart';

/// A revision with a data transaction, which [MockARFSFile] cannot express.
class _Revision extends ARFSFileEntity {
  _Revision()
      : super(
          appName: 'ArDrive-App',
          appVersion: '2.86.0',
          arFS: '0.11',
          driveId: 'drive-id',
          entityType: EntityType.file,
          name: 'holiday.mp4',
          txId: 'metadata-tx',
          unixTime: DateTime.utc(2026, 8, 5),
          id: 'file-id',
          size: 5003,
          lastModifiedDate: DateTime.utc(2026, 8, 5),
          parentFolderId: 'parent-folder-id',
          contentType: 'video/mp4',
          dataTxId: 'data-tx',
        );
}

/// The size ceiling that cannot be reached.
///
/// [DownloadPolicy.singleFileLimit] asks `AppPlatform.isSafari`, which reads
/// the device info **platform channel**. A channel that is not registered - a
/// browser build where the plugin failed to load, a platform that does not
/// answer - throws, and this stands in for that.
class _UnavailablePolicy extends DownloadPolicy {
  const _UnavailablePolicy();

  @override
  Future<DownloadSizeLimit> singleFileLimit({required bool isPublic}) async {
    throw MissingPluginException(
      'No implementation found for method getDeviceInfo',
    );
  }
}

/// Records that a download was started, and finishes it immediately.
class _RecordingDownloader implements ArDriveDownloader {
  int downloadFileCalls = 0;

  @override
  Future<Stream<double>> downloadFile({
    required String txId,
    required int fileSize,
    required String fileName,
    required DateTime lastModifiedDate,
    required String contentType,
    required bool isManifest,
    Completer<String>? cancelWithReason,
    SecretKey? fileKey,
    String? cipher,
    String? cipherIvString,
    bool verifyDownload = false,
  }) async {
    downloadFileCalls++;

    return Stream<double>.fromIterable(const [100.0]);
  }

  @override
  Future<Uint8List> downloadToMemory({
    required String txId,
    required int fileSize,
    required String fileName,
    required DateTime lastModifiedDate,
    required String contentType,
    required bool isManifest,
    Completer<String>? cancelWithReason,
    SecretKey? fileKey,
    String? cipher,
    String? cipherIvString,
    bool verifyDownload = false,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> abortDownload() async {}

  @override
  Future<DataItemIntegrityResult> get integrity async =>
      const DataItemIntegrityResult.notVerified('not under test');

  @override
  Stream<DownloadResumeEvent> get resumeEvents =>
      const Stream<DownloadResumeEvent>.empty();
}

/// The recipient's download, when the size check cannot be run.
void main() {
  test('a size check that throws costs the check, not the download', () async {
    final downloader = _RecordingDownloader();

    // The constructor starts this and discards the future, so an error that
    // escapes [verifyUploadLimitationsAndDownload] is both an unhandled
    // asynchronous error *and* a dialog that sits on "starting" for ever:
    // nothing emits, so nothing - not even `addError` - reports it.
    final cubit = SharedFileDownloadCubit(
      revision: _Revision(),
      arweave: MockArweaveService(),
      crypto: MockArDriveCrypto(),
      arDriveDownloader: downloader,
      downloadPolicy: const _UnavailablePolicy(),
    );

    await expectLater(
      cubit.stream,
      emitsInOrder(<Matcher>[
        isA<FileDownloadInProgress>(),
        isA<FileDownloadWithProgress>(),
        isA<FileDownloadFinishedWithSuccess>(),
      ]),
    );

    expect(downloader.downloadFileCalls, 1);

    await cubit.close();
  });
}
