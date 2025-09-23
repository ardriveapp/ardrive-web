import 'dart:async';
import 'dart:convert';

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
          '${_configService.config.defaultArweaveGatewayForDataRequest.url}/${file.dataTxId}';

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
        case 'text':
        case 'application':
          // Check file size for document preview
          if (file.size! > documentPreviewMaxFileSize) {
            emit(FsEntryPreviewUnavailable());
            return;
          }
          _previewDocument(
            fileKey != null,
            selectedItem,
            previewUrl,
            fileKey: fileKey,
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
    // TODO: Implement PDF preview support
    // - For web: Could use iframe for public PDFs
    // - For mobile: Need PDF viewer package
    // - For private PDFs: Need to decrypt first
    emit(FsEntryPreviewUnavailable());
  }

  Future<void> _preview() async {
    final selectedItem = maybeSelectedItem;

    // initially set to no preview available to help reduce tab flickering
    emit(FsEntryPreviewUnavailable());

    if (selectedItem != null) {
      if (selectedItem.runtimeType == FileDataTableItem) {
        final fileItem = selectedItem as FileDataTableItem;
        
        // Try to preview immediately if we have a dataTxId
        if (fileItem.dataTxId.isNotEmpty) {
          final drive = await _driveDao.driveById(driveId: driveId).getSingleOrNull();
          if (drive != null) {
            // Attempt immediate preview with available data
            await _attemptImmediatePreview(fileItem, drive);
          }
        }
        
        // Still watch for updates in case the file data changes
        _entrySubscription = _driveDao
            .fileById(fileId: selectedItem.id)
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
                '${_configService.config.defaultArweaveGatewayForDataRequest.url}/${file.dataTxId}';

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
                  fileItem.pinnedDataOwnerAddress ==
                          null &&
                      drive.isPrivate,
                  fileItem,
                  previewUrl,
                );
                break;
              case 'video':
                _previewVideo(
                  drive.isPrivate,
                  fileItem,
                  previewUrl,
                );
                break;
              case 'text':
              case 'application':
                // Check file size for document preview
                if (file.size > documentPreviewMaxFileSize) {
                  emit(FsEntryPreviewUnavailable());
                  return;
                }
                _previewDocument(
                  drive.isPrivate,
                  fileItem,
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
  
  Future<void> _attemptImmediatePreview(FileDataTableItem fileItem, Drive drive) async {
    // Check size limits
    if (drive.isPrivate && fileItem.size != null && fileItem.size! > previewMaxFileSize) {
      return; // Wait for database sync for large private files
    }
    
    final contentType = fileItem.contentType;
    final fileExtension = contentType.split('/').last;
    final previewType = contentType.split('/').first;
    final previewUrl = '${_configService.config.defaultArweaveGatewayForDataRequest.url}/${fileItem.dataTxId}';

    if (!_supportedExtension(previewType, fileExtension)) {
      return; // Will be handled by the subscription
    }

    // Attempt immediate preview based on type
    switch (previewType) {
      case 'text':
      case 'application':
        // Check file size for document preview
        if (fileItem.size != null && fileItem.size! > documentPreviewMaxFileSize) {
          return;
        }
        _previewDocument(
          drive.isPrivate,
          fileItem,
          previewUrl,
        );
        break;
      case 'image':
        // For images, we can emit the preview URL immediately
        // The actual loading will happen in the widget
        emit(FsEntryPreviewImage(previewUrl: previewUrl));
        
        // Still trigger the image preview for private decryption if needed
        if (drive.isPrivate && fileItem.pinnedDataOwnerAddress == null) {
          // We need to wait for the database sync to get the full FileEntry
          // for proper image decryption
          return;
        }
        break;
      case 'audio':
        _previewAudio(
          fileItem.pinnedDataOwnerAddress == null && drive.isPrivate,
          fileItem,
          previewUrl,
        );
        break;
      case 'video':
        _previewVideo(
          drive.isPrivate,
          fileItem,
          previewUrl,
        );
        break;
      default:
        // Other types will be handled by the subscription
        break;
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
    late DriveKey? driveKey;

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

    final fileKey = await _driveDao.getFileKey(fileId, driveKey.key);
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

  Future<void> _previewDocument(
    bool isPrivate,
    FileDataTableItem selectedItem,
    String previewUrl, {
    SecretKey? fileKey,
  }) async {

    emit(const FsEntryPreviewLoading());

    try {
      // For manifest files, use the /raw/ endpoint to get the actual JSON content
      String dataUrl = previewUrl;
      if (selectedItem.contentType == 'application/x.arweave-manifest+json') {
        dataUrl = '${_configService.config.defaultArweaveGatewayForDataRequest.url}/raw/${selectedItem.dataTxId}';
      }
      
      // Fetch the document content using cache
      final Uint8List? dataBytes = await _getBytesFromCache(
        dataTxId: selectedItem.dataTxId,
        dataUrl: dataUrl,
      );

      if (dataBytes == null) {
        emit(FsEntryPreviewUnavailable());
        return;
      }

      // Handle decryption for private files
      Uint8List? bytesToDecode = dataBytes;
      final isPinFile = selectedItem.pinnedDataOwnerAddress != null;

      if (isPrivate && !isPinFile) {
        // Get file key if not provided
        final SecretKey? decryptionKey = fileKey ?? await _getFileKey(
          fileId: selectedItem.id,
          driveId: driveId,
          isPrivate: true,
          isPin: isPinFile,
        );

        if (decryptionKey == null) {
          emit(FsEntryPreviewUnavailable());
          return;
        }

        // Decrypt the data
        final decryptedBytes = await _decodePrivateData(
          dataBytes,
          decryptionKey,
          selectedItem.dataTxId,
        );

        if (decryptedBytes == null) {
          emit(FsEntryPreviewUnavailable());
          return;
        }

        bytesToDecode = decryptedBytes;
      }

      // Convert bytes to string
      String content = utf8.decode(bytesToDecode, allowMalformed: true);
      
      // Pretty-print JSON files for better readability
      if (selectedItem.contentType == 'application/json' || 
          selectedItem.contentType == 'application/x.arweave-manifest+json') {
        try {
          final dynamic jsonData = json.decode(content);
          content = const JsonEncoder.withIndent('  ').convert(jsonData);
        } catch (e) {
          // If JSON parsing fails, use the original content
          logger.d('Failed to format JSON: $e');
        }
      }

      emit(FsEntryPreviewText(
        previewUrl: previewUrl,
        filename: selectedItem.name,
        content: content,
        contentType: selectedItem.contentType,
      ));
    } catch (e) {
      logger.e('Error loading document preview', e);
      emit(FsEntryPreviewUnavailable());
    }
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
      case 'text':
      case 'application':
        // Check if it's a document type we support
        final fullContentType = '$previewType/$fileExtension';
        return documentContentTypes.contains(fullContentType);
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
