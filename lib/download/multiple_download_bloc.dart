import 'package:archive/archive_io.dart';
import 'package:ardrive/blocs/file_download/file_download_cubit.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/arfs/repository/arfs_repository.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/download/download_utils.dart';
import 'package:ardrive/entities/constants.dart' as constants;
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:collection/collection.dart';
import 'package:cryptography/cryptography.dart';
// ignore: depend_on_referenced_packages
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

  bool _canceled = false;
  int _currentFileIndex = 0;
  final List<MultiDownloadItem> _skippedFiles = [];
  DriveKey? _driveKey;

  ARFSDriveEntity? _drive;
  late ZipEncoder _zipEncoder;
  late OutputStream _outputStream;
  late List<MultiDownloadItem> _files;
  late String _outFileName;

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
        await _startDownload(event, emit);
      } else if (event is CancelDownload) {
        // signal the download process to exit
        _canceled = true;
      } else if (event is ResumeDownload) {
        await _resumeDownload(event, emit);
      } else if (event is SkipFileAndResumeDownload) {
        await _skipFileAndResumeDownload(event, emit);
      }
    });
  }

  Future<void> _startDownload(
      StartDownload event, Emitter<MultipleDownloadState> emit) async {
    _files = await convertSelectionToMultiDownloadFileList(
        _driveDao, _arfsRepository, event.selectedItems);

    _skippedFiles.clear();

    if (_files.isEmpty) {
      emit(
        const MultipleDownloadFailure(
          FileDownloadFailureReason.unknownError,
        ),
      );
      return;
    }

    MultiDownloadFile? firstOwnedFile = _files.firstWhereOrNull((element) =>
        element is MultiDownloadFile &&
        element.pinnedDataOwnerAddress == null) as MultiDownloadFile?;

    if (firstOwnedFile != null) {
      _drive = await _arfsRepository.getDriveById(firstOwnedFile.driveId);
    }

    bool hasPrivateFiles =
        _drive != null && _drive!.drivePrivacy == DrivePrivacy.private;

    if (await isSizeAboveDownloadSizeLimit(_files, hasPrivateFiles,
        deviceInfo: _deviceInfo)) {
      emit(
        const MultipleDownloadFailure(
          FileDownloadFailureReason.fileAboveLimit,
        ),
      );
      return;
    }

    if (_drive?.drivePrivacy == DrivePrivacy.private) {
      if (_cipherKey != null) {
        _driveKey = await _driveDao.getDriveKey(
          _drive!.driveId,
          _cipherKey,
        );
      } else {
        _driveKey = await _driveDao.getDriveKeyFromMemory(_drive!.driveId);
      }

      if (_driveKey == null) {
        throw StateError('Drive Key not found');
      }
    } else {
      _driveKey = null;
    }

    _initializeEncoder();
    _outFileName =
        event.zipName != null ? '${event.zipName}.zip' : 'Archive.zip';

    await _downloadMultipleFiles(emit);
  }

  Future<void> _resumeDownload(
      ResumeDownload event, Emitter<MultipleDownloadState> emit) async {
    _canceled = false;
    await _downloadMultipleFiles(emit);
  }

  Future<void> _skipFileAndResumeDownload(SkipFileAndResumeDownload event,
      Emitter<MultipleDownloadState> emit) async {
    _canceled = false;
    _skippedFiles.add(_files[_currentFileIndex]);
    _currentFileIndex++;
    await _downloadMultipleFiles(emit);
  }

  void _initializeEncoder() {
    _zipEncoder = ZipEncoder();
    _outputStream = OutputStream(
      byteOrder: LITTLE_ENDIAN,
    );
    _zipEncoder.startEncode(_outputStream, level: Deflate.NO_COMPRESSION);
  }

  Future<void> _downloadMultipleFiles(
      Emitter<MultipleDownloadState> emit) async {
    try {
      while (_currentFileIndex < _files.length) {
        if (_canceled) {
          logger.d('User cancelled multi-file downloading.');
          return;
        }

        emit(
          MultipleDownloadInProgress(
            files: _files,
            currentFileIndex: _currentFileIndex,
          ),
        );

        final file = _files[_currentFileIndex];

        if (file is MultiDownloadFile) {
          // TODO: Use cancelable streaming downloading once it is available in
          // ArDriveHTTP
          final dataBytes = await _downloadService.download(
              file.txId, file.contentType == constants.ContentType.manifest);

          if (_canceled) {
            logger.d('User cancelled multi-file downloading.');
            return;
          }

          Uint8List outputBytes;

          if (file.pinnedDataOwnerAddress == null && _driveKey != null) {
            final fileKey =
                await _driveDao.getFileKey(file.fileId, _driveKey!.key);
            final dataTx = await (_arweave.getTransactionDetails(file.txId));

            try {
              if (dataTx != null) {
                final decryptedData = await _crypto.decryptDataFromTransaction(
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

          _zipEncoder.addFile(ArchiveFile.noCompress(
            file.fileName,
            file.size,
            outputBytes,
          ));
        } else {
          // FOLDER ENTRY
          final dir = file as MultiDownloadFolder;
          final entry =
              ArchiveFile.noCompress(dir.folderPath, 0, Uint8List.fromList([]));
          entry.isFile = false;
          _zipEncoder.addFile(entry);
        }

        _currentFileIndex++;
      }

      _zipEncoder.endEncode();

      emit(MultipleDownloadFinishedWithSuccess(
        bytes: Uint8List.fromList(_outputStream.getBytes()),
        fileName: _outFileName,
        lastModified: DateTime.now(),
        skippedFiles: _skippedFiles,
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
