import 'dart:async';

import 'package:ardrive/blocs/fs_entry_preview/image_preview_notification.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/constants.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
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
  static final ValueNotifier<ImagePreviewNotification?> imagePreviewNotifier =
      ValueNotifier<ImagePreviewNotification?>(null);

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
        _profileCubit = profileCubit,
        _arweave = arweave,
        _crypto = crypto,
        _fileKey = fileKey,
        super(FsEntryPreviewInitial()) {
    if (isSharedFile) {
      _sharedFilePreview(maybeSelectedItem!, fileKey);
    } else {
      _preview();
    }
  }

  Future<void> _sharedFilePreview(
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
          _previewImageSharePage(
            fileKey != null,
            selectedItem,
            previewUrl,
          );
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
        case 'pdf':
          _previewPdf(
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
  }

  void _previewPdf(
    bool isPrivate,
    FileDataTableItem selectedItem,
    String previewUrl,
  ) {
    emit(FsEntryPreviewUnavailable());
  }

  Future<void> _preview() async {
    final selectedItem = maybeSelectedItem;

    // initially set to no preview available to help reduce tab flickering
    emit(FsEntryPreviewUnavailable());

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
                _previewImageDriveExplorer(file, previewUrl);
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
          } else {
            emit(FsEntryPreviewUnavailable());
          }
        });
      } else {
        emit(FsEntryPreviewUnavailable());
      }
    } else {
      emit(FsEntryPreviewUnavailable());
    }
  }

  Future<void> _previewImageDriveExplorer(
    FileEntry file,
    String dataUrl,
  ) async {
    if (file.dataContentType == null) {
      emit(FsEntryPreviewUnavailable());
      return;
    }

    imagePreviewNotifier.value = ImagePreviewNotification(
      isLoading: true,
      filename: file.name,
      contentType: file.dataContentType!,
    );

    emit(FsEntryPreviewImage(previewUrl: dataUrl));

    final Uint8List? dataBytes = await _getBytesFromCache(
      dataTxId: file.dataTxId,
      dataUrl: dataUrl,
    );

    try {
      final driveId = file.driveId;
      final drive = await _driveDao.driveById(driveId: driveId).getSingle();
      final isPinFile = file.pinnedDataOwnerAddress != null;

      switch (drive.privacy) {
        case DrivePrivacyTag.public:
          _emitImagePreview(file, dataUrl, dataBytes: dataBytes);
          break;
        case DrivePrivacyTag.private:
          if (dataBytes == null || isPinFile) {
            _emitImagePreview(file, dataUrl, dataBytes: dataBytes);
            break;
          }

          final fileKey = await _getFileKey(
            fileId: file.id,
            driveId: driveId,
            isPrivate: true,
            isPin: isPinFile,
          );

          final decodedBytes = await _decodePrivateData(
            dataBytes,
            fileKey!,
            file.dataTxId,
          );

          _emitImagePreview(file, dataUrl, dataBytes: decodedBytes);
          break;

        default:
          logger.e('Unknown drive privacy tag: ${drive.privacy}');
          _emitImagePreview(file, dataUrl, dataBytes: dataBytes);
      }
    } catch (_) {
      _emitImagePreview(file, dataUrl);
    }
  }

  void _previewImageSharePage(
    bool isPrivate,
    FileDataTableItem file,
    String previewUrl,
  ) async {
    final isPinFile = file.pinnedDataOwnerAddress != null;

    imagePreviewNotifier.value = ImagePreviewNotification(
      isLoading: true,
      filename: file.name,
      contentType: file.contentType,
    );

    final Uint8List? dataBytes = await _getBytesFromCache(
      dataTxId: file.dataTxId,
      dataUrl: previewUrl,
      withDriveDao: false,
    );

    if (dataBytes == null) {
      emit(FsEntryPreviewUnavailable());
      return;
    }

    if (isPrivate && !isPinFile) {
      if (file.size! >= previewMaxFileSize) {
        emit(FsEntryPreviewUnavailable());
      }

      final fileKey = await _getFileKey(
        fileId: file.id,
        driveId: driveId,
        isPrivate: true,
        isPin: false,
      );
      final decodedBytes = await _decodePrivateData(
        dataBytes,
        fileKey!,
        file.dataTxId,
      );
      imagePreviewNotifier.value = ImagePreviewNotification(
        dataBytes: decodedBytes,
        filename: file.name,
        contentType: file.contentType,
      );
    } else {
      imagePreviewNotifier.value = ImagePreviewNotification(
        dataBytes: dataBytes,
        filename: file.name,
        contentType: file.contentType,
      );
    }

    emit(FsEntryPreviewImage(previewUrl: previewUrl));
  }

  Future<SecretKey?> _getFileKey({
    required String fileId,
    required String driveId,
    required bool isPrivate,
    required bool isPin,
  }) async {
    if (!isPrivate || isPin) {
      return null;
    }

    if (_fileKey != null) {
      return _fileKey;
    }

    final profile = _profileCubit.state;
    late SecretKey? driveKey;

    if (profile is ProfileLoggedIn) {
      driveKey = await _driveDao.getDriveKey(
        driveId,
        profile.user.cipherKey,
      );
    } else {
      driveKey = await _driveDao.getDriveKeyFromMemory(driveId);
    }

    if (driveKey == null) {
      return null;
    }

    final fileKey = await _driveDao.getFileKey(fileId, driveKey);
    return fileKey;
  }

  void _previewAudio(
      bool isPrivate, FileDataTableItem selectedItem, previewUrl) {
    if (isPrivate) {
      emit(FsEntryPreviewUnavailable());
      return;
    }

    emit(FsEntryPreviewAudio(
        filename: selectedItem.name, previewUrl: previewUrl));

    return;
  }

  void _previewVideo(
      bool isPrivate, FileDataTableItem selectedItem, previewUrl) {
    if (isPrivate) {
      emit(FsEntryPreviewUnavailable());
      return;
    }

    emit(FsEntryPreviewVideo(
        filename: selectedItem.name, previewUrl: previewUrl));

    return;
  }

  Future<Uint8List?> _getBytesFromCache({
    required String dataTxId,
    required String dataUrl,
    bool withDriveDao = true,
  }) async {
    Uint8List? dataBytes;

    final cachedBytes = withDriveDao
        ? await _driveDao.getPreviewDataFromMemory(
            dataTxId,
          )
        : null;

    if (cachedBytes == null) {
      try {
        final dataRes = await ArDriveHTTP().getAsBytes(dataUrl);
        dataBytes = dataRes.data;

        await _driveDao.putPreviewDataInMemory(
          dataTxId: dataTxId,
          bytes: dataBytes!,
        );
      } catch (_) {
        dataBytes = null;
      }
    } else {
      dataBytes = cachedBytes;
    }

    return dataBytes;
  }

  Future<Uint8List?> _decodePrivateData(
    Uint8List dataBytes,
    SecretKey fileKey,
    String dataTxId,
  ) async {
    final dataTx = await _getDataTx(dataTxId);

    if (dataTx == null) {
      return null;
    }

    try {
      final decodedBytes = await _crypto.decryptDataFromTransaction(
        dataTx,
        dataBytes,
        fileKey,
      );

      return decodedBytes;
    } catch (e) {
      return null;
    }
  }

  Future<TransactionCommonMixin?> _getDataTx(
    String fileDataTxId,
  ) async {
    final dataTx = await _arweave.getTransactionDetails(fileDataTxId);
    return dataTx;
  }

  void _emitImagePreview(
    FileEntry file,
    String dataUrl, {
    Uint8List? dataBytes,
  }) {
    if (isClosed) {
      return;
    }

    if (file.dataContentType == null) {
      emit(FsEntryPreviewUnavailable());
      return;
    }

    imagePreviewNotifier.value = ImagePreviewNotification(
      dataBytes: dataBytes,
      filename: file.name,
      contentType: file.dataContentType!,
    );
    emit(FsEntryPreviewImage(previewUrl: dataUrl));
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
        return true;
      default:
        return false;
    }
  }

  @override
  Future<void> close() async {
    await _entrySubscription?.cancel();
    return super.close();
  }
}
