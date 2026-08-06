import 'dart:async';
import 'dart:convert';

import 'package:ardrive/blocs/fs_entry_preview/image_preview_notification.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/eml_parser/eml_parser_service.dart';
import 'package:ardrive/services/eml_parser/models/parsed_email.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/constants.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/preview_object_urls.dart';
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

  /// Makes a playable URL out of decrypted bytes. See [PreviewObjectUrls] for
  /// what such a URL may - and may not - be handed to.
  final PreviewObjectUrls _objectUrls;

  /// Every URL [_objectUrls] has handed out, so the bytes behind them are
  /// released when this cubit closes rather than living as long as the tab.
  final List<String> _createdObjectUrls = [];

  /// The data transaction whose PDF bytes are already in flight or already
  /// rendered. See [_previewPdf].
  String? _pdfDataTxId;

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
    PreviewObjectUrls? objectUrls,
  })  : _driveDao = driveDao,
        _configService = configService,
        _profileCubit = profileCubit,
        _arweave = arweave,
        _crypto = crypto,
        _fileKey = fileKey,
        _objectUrls = objectUrls ?? PreviewObjectUrls(),
        super(FsEntryPreviewInitial()) {
    if (isSharedFile) {
      _sharedFilePreview(maybeSelectedItem!, fileKey);
    } else {
      _preview();
    }
  }

  /// Image previews are buffered entirely in memory before being rendered, so
  /// every image — public or private — is capped at [previewMaxFileSize].
  ///
  /// Emits [FsEntryPreviewOversized] and returns `true` when [fileSize] is over
  /// the limit, so callers can bail out *before* fetching a single byte.
  bool _emitOversizedIfOverLimit(int? fileSize) {
    if (fileSize == null || fileSize <= previewMaxFileSize) {
      return false;
    }

    if (!isClosed) {
      emit(FsEntryPreviewOversized(
        fileSize: fileSize,
        maxFileSize: previewMaxFileSize,
      ));
    }

    return true;
  }

  Future<void> _sharedFilePreview(
    ArDriveDataTableItem selectedItem,
    SecretKey? fileKey,
  ) async {
    if (selectedItem is FileDataTableItem) {
      final file = selectedItem;
      // For private files, dataContentType comes from the decrypted metadata JSON
      // For public files, dataContentType comes from the data transaction tags
      // Fall back to filename-based MIME type lookup when not yet available
      String contentType = file.contentType;
      if (contentType.isEmpty || contentType == 'application/octet-stream') {
        // Check for .eml extension explicitly before falling back to lookupMimeType
        if (file.name.toLowerCase().endsWith('.eml')) {
          contentType = 'message/rfc822';
        } else {
          contentType = lookupMimeType(file.name) ?? contentType;
        }
      }
      final fileExtension = contentType.split('/').last;
      final previewType = contentType.split('/').first;
      final previewUrl =
          '${_configService.config.arweaveGatewayForDataRequest.url}/${file.dataTxId}';

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
            contentType,
          );
          break;

        case 'video':
          _previewVideo(
            fileKey != null,
            selectedItem,
            previewUrl,
            contentType,
          );
          break;
        case 'text':
        case 'application':
        case 'message':
          // A PDF is rasterised rather than decoded as text, so the document
          // size cap - which exists because documents are decoded into a string
          // here - is not the one that applies to it. [_previewPdf] applies the
          // in-memory preview cap instead.
          if (pdfContentTypes.contains(contentType)) {
            _previewPdf(
              fileKey != null,
              selectedItem,
              previewUrl,
            );
            break;
          }

          // Check file size for document preview
          if (file.size != null && file.size! > documentPreviewMaxFileSize) {
            emit(FsEntryPreviewUnavailable());
            return;
          }
          // Check if it's an email file (use resolved contentType for private files)
          if (contentType == 'message/rfc822') {
            _previewEmail(
              fileKey != null,
              selectedItem,
              previewUrl,
              fileKey: fileKey,
            );
          } else {
            _previewDocument(
              fileKey != null,
              selectedItem,
              previewUrl,
              fileKey: fileKey,
            );
          }
          break;

        default:
          emit(FsEntryPreviewUnavailable());
      }
    } else {
      emit(FsEntryPreviewUnavailable());
    }
  }

  /// A PDF's plaintext, for the rasteriser to turn into page images.
  ///
  /// Public bytes come through the same gateway waterfall as every other
  /// preview; private bytes are fetched and decrypted here, in memory, and go
  /// straight into the viewer. Neither ever becomes a blob URL, a temp file, or
  /// DOM: the viewer draws pages as images, so a PDF that carries JavaScript
  /// carries it nowhere - which is what
  /// `docs/FILE_SHARING_REDESIGN_PLAN.md` §4.3 requires of bytes from an
  /// untrusted transaction, and it is load-bearing because a recipient's access
  /// key can be sitting in this origin's `sessionStorage`.
  ///
  /// A *public* file whose bytes will not come is not a dead end: the state
  /// still carries the gateway URL, and the viewer degrades to offering it in a
  /// new tab, which is all this path could ever do before. A private file has
  /// no such URL, because every gateway holds only its ciphertext.
  ///
  /// [size] is the freshest size known for the file; the database row is more
  /// current than the selected item when the drive explorer has just synced.
  Future<void> _previewPdf(
    bool isPrivate,
    FileDataTableItem selectedItem,
    String previewUrl, {
    int? size,
  }) async {
    // Pinned files are public bytes wearing a private drive's clothes, so they
    // take the public path.
    final isPinFile = selectedItem.pinnedDataOwnerAddress != null;
    final isEncrypted = isPrivate && !isPinFile;

    // The file is buffered whole to be rasterised, so the cap is checked before
    // a single byte is requested.
    if (_emitOversizedIfOverLimit(size ?? selectedItem.size)) {
      return;
    }

    // The drive explorer previews once immediately and again on every database
    // change; a PDF can be a hundred megabytes, so the same one is not fetched
    // twice. Claimed synchronously, before the first await, or two calls that
    // arrive together would both get past it.
    if (_pdfDataTxId == selectedItem.dataTxId) {
      return;
    }

    _pdfDataTxId = selectedItem.dataTxId;

    // A private file with no key is not a preview that fails; it is one that
    // must never be attempted. Checked before anything is fetched, so the
    // ciphertext of a file this viewer cannot read is never even requested.
    SecretKey? fileKey;

    if (isEncrypted) {
      fileKey = await _getFileKey(
        fileId: selectedItem.id,
        driveId: driveId,
        isPrivate: true,
        isPin: false,
      );

      if (fileKey == null) {
        _pdfDataTxId = null;
        _emitUnavailable();
        return;
      }
    }

    if (isClosed) {
      return;
    }

    emit(const FsEntryPreviewLoading());

    // Deliberately not routed through the preview vault: that cache is
    // unbounded, and a PDF is the other preview type that can be a hundred
    // megabytes of it.
    Uint8List? dataBytes;

    try {
      dataBytes = await _fetchPreviewBytes(selectedItem.dataTxId);
    } catch (e) {
      logger.d('Could not fetch the bytes for a PDF preview: $e');
      dataBytes = null;
    }

    if (dataBytes != null && isEncrypted) {
      dataBytes = await _decodePrivateData(
        dataBytes,
        fileKey!,
        selectedItem.dataTxId,
      );
    }

    if (isClosed) {
      return;
    }

    if (dataBytes == null) {
      // Nothing was rendered, so a later database change is free to try again.
      _pdfDataTxId = null;

      if (isEncrypted) {
        // No plaintext, and no URL to offer instead.
        _emitUnavailable();
        return;
      }
    }

    emit(FsEntryPreviewPdf(
      previewUrl: previewUrl,
      filename: selectedItem.name,
      pdfBytes: dataBytes,
      canOpenOnGateway: !isEncrypted,
    ));
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
            // For private files, dataContentType comes from the decrypted metadata JSON
            // For public files, dataContentType comes from the data transaction tags
            // Fall back to filename-based MIME type lookup when not yet available
            String? contentType = file.dataContentType;
            if (contentType == null || contentType == 'application/octet-stream') {
              // Check for .eml extension explicitly before falling back to lookupMimeType
              if (file.name.toLowerCase().endsWith('.eml')) {
                contentType = 'message/rfc822';
              } else {
                contentType = lookupMimeType(file.name) ?? contentType ?? 'application/octet-stream';
              }
            }
            final fileExtension = contentType.split('/').last;
            final previewType = contentType.split('/').first;
            final previewUrl =
                '${_configService.config.arweaveGatewayForDataRequest.url}/${file.dataTxId}';

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
                  drive.isPrivate,
                  fileItem,
                  previewUrl,
                  contentType,
                );
                break;
              case 'video':
                _previewVideo(
                  drive.isPrivate,
                  fileItem,
                  previewUrl,
                  contentType,
                );
                break;
              case 'text':
              case 'application':
              case 'message':
                if (pdfContentTypes.contains(contentType)) {
                  // The database row is fresher than the selected item here.
                  _previewPdf(
                    drive.isPrivate,
                    fileItem,
                    previewUrl,
                    size: file.size,
                  );
                  break;
                }

                // Check file size for document preview
                if (file.size > documentPreviewMaxFileSize) {
                  emit(FsEntryPreviewUnavailable());
                  return;
                }
                // Check if it's an email file
                if (contentType == 'message/rfc822') {
                  _previewEmail(
                    drive.isPrivate,
                    fileItem,
                    previewUrl,
                  );
                } else {
                  _previewDocument(
                    drive.isPrivate,
                    fileItem,
                    previewUrl,
                  );
                }
                break;
              default:
                emit(FsEntryPreviewUnavailable());
            }
          } else {
            // Only reachable for a private file over the in-memory preview
            // limit — nothing is fetched for it.
            if (!_emitOversizedIfOverLimit(file.size)) {
              emit(FsEntryPreviewUnavailable());
            }
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

    // For private files, dataContentType comes from the decrypted metadata JSON
    // For public files, dataContentType comes from the data transaction tags
    // Fall back to filename-based MIME type lookup when not yet available
    String contentType = fileItem.contentType;
    if (contentType.isEmpty || contentType == 'application/octet-stream') {
      // Check for .eml extension explicitly before falling back to lookupMimeType
      if (fileItem.name.toLowerCase().endsWith('.eml')) {
        contentType = 'message/rfc822';
      } else {
        contentType = lookupMimeType(fileItem.name) ?? contentType;
      }
    }
    final fileExtension = contentType.split('/').last;
    final previewType = contentType.split('/').first;
    final previewUrl = '${_configService.config.arweaveGatewayForDataRequest.url}/${fileItem.dataTxId}';

    if (!_supportedExtension(previewType, fileExtension)) {
      return; // Will be handled by the subscription
    }

    // Attempt immediate preview based on type
    switch (previewType) {
      case 'text':
      case 'application':
      case 'message':
        if (pdfContentTypes.contains(contentType)) {
          _previewPdf(
            drive.isPrivate,
            fileItem,
            previewUrl,
          );
          break;
        }

        // Check file size for document preview
        if (fileItem.size != null && fileItem.size! > documentPreviewMaxFileSize) {
          return;
        }
        // Check if it's an email file (use resolved contentType for private files)
        if (contentType == 'message/rfc822') {
          _previewEmail(
            drive.isPrivate,
            fileItem,
            previewUrl,
          );
        } else {
          _previewDocument(
            drive.isPrivate,
            fileItem,
            previewUrl,
          );
        }
        break;
      case 'image':
        // Images are buffered in memory, public ones included — never start a
        // preview we cannot hold.
        if (_emitOversizedIfOverLimit(fileItem.size)) {
          return;
        }

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
          drive.isPrivate,
          fileItem,
          previewUrl,
          contentType,
        );
        break;
      case 'video':
        _previewVideo(
          drive.isPrivate,
          fileItem,
          previewUrl,
          contentType,
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

    // Public images used to be fetched with no cap at all — they are buffered
    // in memory just like private ones, so cap both before fetching.
    if (_emitOversizedIfOverLimit(file.size)) {
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
    // The size gate has to run before anything is fetched: this used to sit
    // after the download and was missing its `return`, so an over-limit private
    // image was downloaded and decrypted anyway.
    if (_emitOversizedIfOverLimit(file.size)) {
      return;
    }

    final isPinFile = file.pinnedDataOwnerAddress != null;

    imagePreviewNotifier.value = ImagePreviewNotification(
      isLoading: true,
      filename: file.name,
      contentType: file.contentType,
    );

    final Uint8List? dataBytes = await _getBytesFromCache(
      dataTxId: file.dataTxId,
      withDriveDao: false,
    );

    if (dataBytes == null) {
      emit(FsEntryPreviewUnavailable());
      return;
    }

    if (isPrivate && !isPinFile) {
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

  Future<void> _previewAudio(
    bool isPrivate,
    FileDataTableItem selectedItem,
    String previewUrl,
    String contentType,
  ) async {
    final url = await _mediaUrl(
      isPrivate,
      selectedItem,
      previewUrl,
      contentType,
    );

    if (url == null || isClosed) {
      return;
    }

    emit(FsEntryPreviewAudio(
        filename: selectedItem.name, previewUrl: url));
  }

  Future<void> _previewVideo(
    bool isPrivate,
    FileDataTableItem selectedItem,
    String previewUrl,
    String contentType,
  ) async {
    final url = await _mediaUrl(
      isPrivate,
      selectedItem,
      previewUrl,
      contentType,
    );

    if (url == null || isClosed) {
      return;
    }

    emit(FsEntryPreviewVideo(
        filename: selectedItem.name, previewUrl: url));
  }

  /// The URL the player should play, or `null` when there is not going to be
  /// one — in which case the state has already been set to say why.
  ///
  /// Public bytes stream straight from the gateway, as they always have.
  /// Private bytes have no URL of their own — every gateway holds only
  /// ciphertext — so under the preview cap they are fetched, decrypted, and
  /// handed to the player from memory, which is the same shape as the image
  /// path. Streaming a private file that is *over* the cap is Phase 2 work: it
  /// needs the CTR start-offset decryptor to turn a byte range into plaintext.
  ///
  /// Pinned files are public bytes wearing a private drive's clothes, so they
  /// take the public path.
  Future<String?> _mediaUrl(
    bool isPrivate,
    FileDataTableItem selectedItem,
    String previewUrl,
    String contentType,
  ) async {
    final isPinFile = selectedItem.pinnedDataOwnerAddress != null;

    if (!isPrivate || isPinFile) {
      return previewUrl;
    }

    // The bytes are buffered whole, so the size gate runs before anything is
    // fetched.
    if (_emitOversizedIfOverLimit(selectedItem.size)) {
      return null;
    }

    // A private file with no key is not a preview that failed; it is one that
    // must never be attempted. Checked before a single byte is requested.
    final fileKey = await _getFileKey(
      fileId: selectedItem.id,
      driveId: driveId,
      isPrivate: true,
      isPin: false,
    );

    if (fileKey == null) {
      _emitUnavailable();
      return null;
    }

    if (isClosed) {
      return null;
    }

    emit(const FsEntryPreviewLoading());

    // Deliberately not routed through the preview vault: that cache is
    // unbounded, and media is the one preview type that can be a hundred
    // megabytes of it.
    Uint8List? dataBytes;

    try {
      dataBytes = await _fetchPreviewBytes(selectedItem.dataTxId);
    } catch (e) {
      logger.d('Could not fetch the bytes for a media preview: $e');
      dataBytes = null;
    }

    if (dataBytes == null) {
      _emitUnavailable();
      return null;
    }

    final decryptedBytes = await _decodePrivateData(
      dataBytes,
      fileKey,
      selectedItem.dataTxId,
    );

    if (decryptedBytes == null) {
      _emitUnavailable();
      return null;
    }

    final objectUrl = _objectUrls.create(decryptedBytes, contentType);

    if (objectUrl == null) {
      _emitUnavailable();
      return null;
    }

    _createdObjectUrls.add(objectUrl);

    return objectUrl;
  }

  void _emitUnavailable() {
    if (!isClosed) {
      emit(FsEntryPreviewUnavailable());
    }
  }

  Future<void> _previewDocument(
    bool isPrivate,
    FileDataTableItem selectedItem,
    String previewUrl, {
    SecretKey? fileKey,
  }) async {

    emit(const FsEntryPreviewLoading());

    try {
      // For manifest files, the /raw/ endpoint is used to get the actual JSON
      // content instead of the resolved manifest index.
      final isManifest =
          selectedItem.contentType == 'application/x.arweave-manifest+json';

      // Fetch the document content using cache
      final Uint8List? dataBytes = await _getBytesFromCache(
        dataTxId: selectedItem.dataTxId,
        isManifest: isManifest,
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
        fileItem: selectedItem,
      ));
    } catch (e) {
      logger.e('Error loading document preview', e);
      emit(FsEntryPreviewUnavailable());
    }
  }

  Future<void> _previewEmail(
    bool isPrivate,
    FileDataTableItem selectedItem,
    String previewUrl, {
    SecretKey? fileKey,
  }) async {
    emit(const FsEntryPreviewLoading());

    try {
      // Fetch the email file using cache
      final Uint8List? dataBytes = await _getBytesFromCache(
        dataTxId: selectedItem.dataTxId,
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
        final SecretKey? decryptionKey = fileKey ??
            await _getFileKey(
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
      final String emlContent = utf8.decode(bytesToDecode, allowMalformed: true);

      // Parse using JS interop
      final ParsedEmail parsedEmail = await EmlParserService.parseEml(emlContent);

      emit(FsEntryPreviewEmail(
        previewUrl: previewUrl,
        filename: selectedItem.name,
        email: parsedEmail,
      ));
    } catch (e) {
      logger.e('Error loading email preview', e);
      emit(FsEntryPreviewUnavailable());
    }
  }

  Future<Uint8List?> _getBytesFromCache({
    required String dataTxId,
    bool withDriveDao = true,
    bool isManifest = false,
  }) async {
    Uint8List? dataBytes;

    final cachedBytes = withDriveDao
        ? await _driveDao.getPreviewDataFromMemory(
            dataTxId,
          )
        : null;

    if (cachedBytes == null) {
      try {
        final fetchedBytes = await _fetchPreviewBytes(
          dataTxId,
          isManifest: isManifest,
        );

        await _driveDao.putPreviewDataInMemory(
          dataTxId: dataTxId,
          bytes: fetchedBytes,
        );

        dataBytes = fetchedBytes;
      } catch (_) {
        dataBytes = null;
      }
    } else {
      dataBytes = cachedBytes;
    }

    return dataBytes;
  }

  /// Fetches preview bytes through the shared multi-gateway fallback layer
  /// (primary → GAR gateways → arweave.net) instead of hitting the primary data
  /// gateway directly, so a dead or blackholed gateway still yields a preview.
  ///
  /// This is the same path the download flow uses — see [DataGatewayFallback]
  /// and `ArDriveDownloader`.
  Future<Uint8List> _fetchPreviewBytes(
    String dataTxId, {
    bool isManifest = false,
  }) async {
    final gatewayFallback = _arweave.gatewayFallback;

    // Manifests must be read from the `/raw/` endpoint, otherwise the gateway
    // resolves them to their index path instead of returning the manifest.
    final response = isManifest
        ? await gatewayFallback.fetchManifestWithFallback(
            dataTxId,
            _arweave.client,
          )
        : await gatewayFallback.fetchData(
            dataTxId,
            _arweave.client,
          );

    return response.bodyBytes;
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
      case 'message':
        // Check if it's a document type we support
        final fullContentType = '$previewType/$fileExtension';
        // `application/pdf` is a first-segment `application` type, which is why
        // the old `case 'pdf':` above could never be reached and PDFs were
        // reported as unpreviewable.
        return documentContentTypes.contains(fullContentType) ||
            pdfContentTypes.contains(fullContentType);
      default:
        return false;
    }
  }

  @override
  Future<void> close() async {
    // Decrypted media outlives the widget that played it unless the URL is
    // released, so a recipient who opens and closes a preview does not leave
    // the plaintext sitting in the tab.
    for (final objectUrl in _createdObjectUrls) {
      _objectUrls.revoke(objectUrl);
    }

    _createdObjectUrls.clear();

    await _entrySubscription?.cancel();
    return super.close();
  }
}
