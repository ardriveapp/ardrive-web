import 'dart:async';

import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/pages.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/constants.dart';
import 'package:ardrive/utils/mime_lookup.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'fs_entry_preview_state.dart';

class FsEntryPreviewCubit extends Cubit<FsEntryPreviewState> {
  final String driveId;
  final ArDriveDataTableItem? maybeSelectedItem;

  final DriveDao _driveDao;
  final ConfigService _configService;
  final ArweaveService _arweave;
  final ProfileCubit _profileCubit;
  final ArDriveCrypto _crypto;

  final SecretKey? _fileKey;

  StreamSubscription? _entrySubscription;

  final previewMaxFileSize = 1024 * 1024 * 100;
  final allowedPreviewContentTypes = [];

  FsEntryPreviewCubit({
    required this.driveId,
    this.maybeSelectedItem,
    required DriveDao driveDao,
    required ConfigService configService,
    required ArweaveService arweave,
    required ProfileCubit profileCubit,
    required ArDriveCrypto crypto,
    SecretKey? fileKey,
    bool isSharedFile = false,
  })  : _driveDao = driveDao,
        _configService = configService,
        _arweave = arweave,
        _profileCubit = profileCubit,
        _crypto = crypto,
        _fileKey = fileKey,
        super(FsEntryPreviewInitial()) {
    if (isSharedFile) {
      sharedFilePreview(maybeSelectedItem!, fileKey);
    } else {
      preview();
    }
  }

  Future<void> sharedFilePreview(
    ArDriveDataTableItem selectedItem,
    SecretKey? fileKey,
  ) async {
    if (selectedItem is FileDataTableItem) {
      final file = selectedItem;
      final contentType = file.contentType;
      final fileExtension = contentType.split('/').last;
      final previewType = contentType.split('/').first;
      final previewUrl =
          '${_configService.config.defaultArweaveGatewayUrl}/${file.dataTxId}';

      if (!_supportedExtension(previewType, fileExtension)) {
        emit(FsEntryPreviewUnavailable());
        return;
      }

      switch (previewType) {
        case 'image':
          final data = await _getPreviewData(file, previewUrl);

          if (data != null) {
            emit(FsEntryPreviewImage(imageBytes: data, previewUrl: previewUrl));
          } else {
            emit(FsEntryPreviewUnavailable());
          }

          break;

        case 'audio':
          _previewAudio(
            fileKey != null,
            selectedItem,
            previewUrl,
          );
          break;

        case 'video':
          _previewVideo(
            fileKey != null,
            selectedItem,
            previewUrl,
          );
          break;

        default:
          emit(FsEntryPreviewUnavailable());
      }
    } else {
      emit(FsEntryPreviewUnavailable());
    }

    return Future.value();
  }

  Future<Uint8List?> _getPreviewData(
    FileDataTableItem file,
    String previewUrl,
  ) async {
    final dataTx = await _getTxDetails(file);

    if (dataTx == null) {
      emit(FsEntryPreviewUnavailable());
      return null;
    }

    final dataRes = await ArDriveHTTP().getAsBytes(previewUrl);

    final isPinFile = file.pinnedDataOwnerAddress != null;

    if (_fileKey != null && !isPinFile) {
      if (file.size! >= previewMaxFileSize) {
        emit(FsEntryPreviewUnavailable());
        return null;
      }

      try {
        final decodedBytes = await _crypto.decryptTransactionData(
          dataTx,
          dataRes.data,
          _fileKey!,
        );

        return decodedBytes;
      } catch (e) {
        emit(FsEntryPreviewUnavailable());
        return Future.value();
      }
    }

    return dataRes.data;
  }

  Future<TransactionCommonMixin?> _getTxDetails(FileDataTableItem file) async {
    final dataTx = await _arweave.getTransactionDetails(file.dataTxId);

    return dataTx;
  }

  Future<void> preview() async {
    final selectedItem = maybeSelectedItem;
    if (selectedItem != null) {
      if (selectedItem.runtimeType == FileDataTableItem) {
        _entrySubscription = _driveDao
            .fileById(driveId: driveId, fileId: selectedItem.id)
            .watchSingle()
            .listen((file) async {
          final drive = await _driveDao.driveById(driveId: driveId).getSingle();

          if ((drive.isPrivate && file.size <= previewMaxFileSize) ||
              drive.isPublic) {
            final contentType =
                file.dataContentType ?? lookupMimeType(file.name);
            final fileExtension = contentType?.split('/').last;
            final previewType = contentType?.split('/').first;
            final previewUrl =
                '${_configService.config.defaultArweaveGatewayUrl}/${file.dataTxId}';

            if (!_supportedExtension(previewType, fileExtension)) {
              emit(FsEntryPreviewUnavailable());
              return;
            }

            switch (previewType) {
              case 'image':
                emitImagePreview(file, previewUrl);
                break;

              case 'audio':
                _previewAudio(
                  (selectedItem as FileDataTableItem).pinnedDataOwnerAddress ==
                          null &&
                      drive.isPrivate,
                  selectedItem,
                  previewUrl,
                );
                break;
              case 'video':
                _previewVideo(
                  drive.isPrivate,
                  selectedItem as FileDataTableItem,
                  previewUrl,
                );
                break;
              default:
                emit(FsEntryPreviewUnavailable());
            }
          }
        });
      }
    } else {
      emit(FsEntryPreviewUnavailable());
    }
  }

  void _previewAudio(
      bool isPrivate, FileDataTableItem selectedItem, previewUrl) {
    if (_configService.config.enableAudioPreview) {
      if (isPrivate) {
        emit(FsEntryPreviewUnavailable());
        return;
      }

      emit(FsEntryPreviewAudio(
          filename: selectedItem.name, previewUrl: previewUrl));

      return;
    }

    emit(FsEntryPreviewUnavailable());
  }

  void _previewVideo(
      bool isPrivate, FileDataTableItem selectedItem, previewUrl) {
    if (_configService.config.enableVideoPreview) {
      if (isPrivate) {
        emit(FsEntryPreviewUnavailable());
        return;
      }

      emit(FsEntryPreviewVideo(
          filename: selectedItem.name, previewUrl: previewUrl));

      return;
    }

    emit(FsEntryPreviewUnavailable());
  }

  Future<void> emitImagePreview(FileEntry file, String dataUrl) async {
    try {
      emit(const FsEntryPreviewLoading());

      final dataTx = await _arweave.getTransactionDetails(file.dataTxId);

      if (dataTx == null) {
        emit(FsEntryPreviewFailure());
        return;
      }

      late Uint8List dataBytes;

      final cachedBytes = await _driveDao.getPreviewDataFromMemory(dataTx.id);

      if (cachedBytes == null) {
        final dataRes = await ArDriveHTTP().getAsBytes(dataUrl);
        dataBytes = dataRes.data;

        await _driveDao.putPreviewDataInMemory(
          dataTxId: dataTx.id,
          bytes: dataBytes,
        );
      } else {
        dataBytes = cachedBytes;
      }

      final drive = await _driveDao.driveById(driveId: driveId).getSingle();

      switch (drive.privacy) {
        case DrivePrivacyTag.public:
          emit(
            FsEntryPreviewImage(imageBytes: dataBytes, previewUrl: dataUrl),
          );
          break;
        case DrivePrivacyTag.private:
          final profile = _profileCubit.state;
          SecretKey? driveKey;

          final isPinFile = file.pinnedDataOwnerAddress != null;

          if (isPinFile) {
            emit(
              FsEntryPreviewImage(imageBytes: dataBytes, previewUrl: dataUrl),
            );
            break;
          }

          if (profile is ProfileLoggedIn) {
            driveKey = await _driveDao.getDriveKey(
              drive.id,
              profile.cipherKey,
            );
          } else {
            driveKey = await _driveDao.getDriveKeyFromMemory(driveId);
          }

          if (driveKey == null) {
            throw StateError('Drive Key not found');
          }

          final fileKey = await _driveDao.getFileKey(file.id, driveKey);
          final decodedBytes = await _crypto.decryptTransactionData(
            dataTx,
            dataBytes,
            fileKey,
          );
          emit(
            FsEntryPreviewImage(imageBytes: decodedBytes, previewUrl: dataUrl),
          );
          break;

        default:
          emit(FsEntryPreviewFailure());
      }
    } catch (err) {
      emit(FsEntryPreviewFailure());
    }
  }

  bool _supportedExtension(String? previewType, String? fileExtension) {
    if (previewType == null || fileExtension == null) {
      return false;
    }

    switch (previewType) {
      case 'image':
        return supportedImageTypesInFilePreview
            .any((element) => element.contains(fileExtension));
      case 'audio':
        return audioContentTypes
            .any((element) => element.contains(fileExtension));
      case 'video':
        return videoContentTypes
            .any((element) => element.contains(fileExtension));
      default:
        return false;
    }
  }

  @override
  Future<void> close() {
    _entrySubscription?.cancel();
    return super.close();
  }
}
