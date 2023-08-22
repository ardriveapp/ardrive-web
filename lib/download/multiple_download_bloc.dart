import 'package:archive/archive_io.dart';
import 'package:ardrive/blocs/file_download/file_download_cubit.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/arfs/repository/arfs_repository.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:cryptography/cryptography.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'limits.dart';

part 'multiple_download_event.dart';
part 'multiple_download_state.dart';

class MultipleDownloadBloc
    extends Bloc<MultipleDownloadEvent, MultipleDownloadState> {
  final DownloadService _downloadService;
  final ArweaveService _arweave;
  final DriveDao _driveDao;
  final ARFSRepository _arfsRepository;
  final ArDriveCrypto _crypto;
  final SecretKey? _cipherKey;
  final DeviceInfoPlugin? _deviceInfo;

  bool canceled = false;
  int currentFileIndex = 0;
  SecretKey? driveKey;

  late ARFSDriveEntity drive;
  late ZipEncoder zipEncoder;
  late OutputStream outputStream;
  late List<ARFSFileEntity> items;
  late String outFileName;

  MultipleDownloadBloc(
      {required DownloadService downloadService,
      required DriveDao driveDao,
      required ArweaveService arweave,
      required ARFSRepository arfsRepository,
      required ArDriveCrypto crypto,
      DeviceInfoPlugin? deviceInfo,
      SecretKey? cipherKey})
      : _downloadService = downloadService,
        _driveDao = driveDao,
        _arweave = arweave,
        _arfsRepository = arfsRepository,
        _crypto = crypto,
        _cipherKey = cipherKey,
        _deviceInfo = deviceInfo,
        super(MultipleDownloadInitial()) {
    on<MultipleDownloadEvent>((event, emit) async {
      if (event is StartDownload) {
        await startDownload(event, emit);
      } else if (event is CancelDownload) {
        // signal the download process to exit
        canceled = true;
      } else if (event is ResumeDownload) {
        await resumeDownload(event, emit);
      }
    });
  }

  Future<void> startDownload(
      StartDownload event, Emitter<MultipleDownloadState> emit) async {
    items = event.items;

    // check all files from same drive
    var firstFile = items[0];

    // Currently assumes all files from the same drive. May need code like below
    // to verify and emit error if not all files are from the same drive.
    // if (!items.every((file) => file.driveId == firstFile.driveId)) {
    //   // TODO emit error event here and exit
    // }

    drive = await _arfsRepository.getDriveById(firstFile.driveId);

    if (await isSizeAboveDownloadSizeLimit(
        items, drive.drivePrivacy == DrivePrivacy.public,
        deviceInfo: _deviceInfo)) {
      emit(
        const MultipleDownloadFailure(
          FileDownloadFailureReason.fileAboveLimit,
        ),
      );
      return;
    }

    if (drive.drivePrivacy == DrivePrivacy.private) {
      if (_cipherKey != null) {
        driveKey = await _driveDao.getDriveKey(
          drive.driveId,
          _cipherKey!,
        );
      } else {
        driveKey = await _driveDao.getDriveKeyFromMemory(drive.driveId);
      }

      if (driveKey == null) {
        throw StateError('Drive Key not found');
      }
    }

    _initializeEncoder();
    outFileName =
        event.folderName != null ? '${event.folderName}.zip' : 'Archive.zip';

    await _downloadMultipleFiles(emit);
  }

  Future<void> resumeDownload(
      ResumeDownload event, Emitter<MultipleDownloadState> emit) async {
    canceled = false;
    await _downloadMultipleFiles(emit);
  }

  void _initializeEncoder() {
    zipEncoder = ZipEncoder();
    outputStream = OutputStream(
      byteOrder: LITTLE_ENDIAN,
    );
    zipEncoder.startEncode(outputStream, level: Deflate.NO_COMPRESSION);
  }

  Future<void> _downloadMultipleFiles(
      Emitter<MultipleDownloadState> emit) async {
    try {
      final files = items.whereType<ARFSFileEntity>().toList();

      while (currentFileIndex < files.length) {
        if (canceled) {
          logger.d('User cancelled multi-file downloading.');
          return;
        }

        emit(
          MultipleDownloadInProgress(
            files: files,
            currentFileIndex: currentFileIndex,
          ),
        );

        final file = files[currentFileIndex];

        // TODO: Use cancelable streaming downloading once it is available in
        // ArDriveHTTP
        final dataBytes = await _downloadService.download(file.txId);

        if (canceled) {
          logger.d('User cancelled multi-file downloading.');
          return;
        }

        Uint8List outputBytes;

        if (drive.drivePrivacy == DrivePrivacy.private) {
          final fileKey = await _driveDao.getFileKey(file.id, driveKey!);
          final dataTx = await (_arweave.getTransactionDetails(file.txId));

          try {
            if (dataTx != null) {
              final decryptedData = await _crypto.decryptTransactionData(
                dataTx,
                dataBytes,
                fileKey,
              );

              outputBytes = decryptedData;
            } else {
              logger.e('Error decrypting file: dataTx is null');
              emit(const MultipleDownloadFailure(
                  FileDownloadFailureReason.unknownError));
              return;
            }
          } catch (e) {
            logger.e('Error decrypting file: ${e.toString()}');
            emit(const MultipleDownloadFailure(
                FileDownloadFailureReason.unknownError));
            return;
          }
        } else {
          outputBytes = dataBytes;
        }

        zipEncoder.addFile(ArchiveFile.noCompress(
          file.name,
          file.size,
          outputBytes,
        ));

        currentFileIndex++;
      }

      zipEncoder.endEncode();

      emit(MultipleDownloadFinishedWithSuccess(
        bytes: Uint8List.fromList(outputStream.getBytes()),
        fileName: outFileName,
        lastModified: DateTime.now(),
      ));
    } catch (e) {
      if (e is ArDriveHTTPException) {
        if (e.statusCode == 400) {
          emit(const MultipleDownloadFailure(
              FileDownloadFailureReason.fileNotFound));
        } else {
          emit(const MultipleDownloadFailure(
              FileDownloadFailureReason.networkConnectionError));
        }
      } else {
        emit(const MultipleDownloadFailure(
            FileDownloadFailureReason.unknownError));
      }
      logger.d('Multi-file Download Exception: ${e.toString()}');
    }
  }
}
