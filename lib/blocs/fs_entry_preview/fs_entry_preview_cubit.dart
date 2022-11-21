import 'dart:async';

import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/constants.dart';
import 'package:ardrive/utils/mime_lookup.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

part 'fs_entry_preview_state.dart';

class FsEntryPreviewCubit extends Cubit<FsEntryPreviewState> {
  final String driveId;
  final SelectedItem? maybeSelectedItem;

  final DriveDao _driveDao;
  final AppConfig _config;
  final ArweaveService _arweave;
  final ProfileCubit _profileCubit;

  StreamSubscription? _entrySubscription;
  final AudioPlayer audioPlayer = AudioPlayer();

  final previewMaxFileSize = 1024 * 1024 * 100;
  final allowedPreviewContentTypes = [];

  FsEntryPreviewCubit({
    required this.driveId,
    this.maybeSelectedItem,
    required DriveDao driveDao,
    required AppConfig config,
    required ArweaveService arweave,
    required ProfileCubit profileCubit,
  })  : _driveDao = driveDao,
        _config = config,
        _arweave = arweave,
        _profileCubit = profileCubit,
        super(FsEntryPreviewInitial()) {
    preview();
  }

  Future<void> preview() async {
    final selectedItem = maybeSelectedItem;
    if (selectedItem != null) {
      if (selectedItem.runtimeType == SelectedFile) {
        _entrySubscription = _driveDao
            .fileById(driveId: driveId, fileId: selectedItem.id)
            .watchSingle()
            .listen((file) async {
          if (file.size <= previewMaxFileSize) {
            final contentType =
                file.dataContentType ?? lookupMimeType(file.name);
            final fileExtension = contentType?.split('/').last;
            final previewType = contentType?.split('/').first;
            final previewUrl =
                '${_config.defaultArweaveGatewayUrl}/${file.dataTxId}';
            if (!_supportedExtension(previewType, fileExtension)) {
              emit(FsEntryPreviewUnavailable());
              return;
            }

            switch (previewType) {
              case 'image':
                audioPlayer.pause();
                emitImagePreview(file, previewUrl);
                break;

              /// Enable more previews in the future after dealing
              /// with state and widget disposal

              case 'audio':
                emitAudioPreview(file, previewUrl);
                break;
              // case 'video':
              //   emit(FsEntryPreviewVideo(previewUrl: previewUrl));
              //   break;
              // case 'text':
              //   emit(FsEntryPreviewText(previewUrl: previewUrl));
              //   break;

              default:
                audioPlayer.pause();
                emit(FsEntryPreviewUnavailable());
            }
          }
        });
      }
    } else {
      audioPlayer.pause();
      emit(FsEntryPreviewUnavailable());
    }
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
        final dataRes = await http.get(Uri.parse(dataUrl));
        dataBytes = dataRes.bodyBytes;
        await _driveDao.putPreviewDataInMemory(
          dataTxId: dataTx.id,
          bytes: dataBytes,
        );
      } else {
        dataBytes = cachedBytes;
      }

      final drive = await _driveDao.driveById(driveId: driveId).getSingle();
      switch (drive.privacy) {
        case DrivePrivacy.public:
          emit(
            FsEntryPreviewImage(imageBytes: dataBytes, previewUrl: dataUrl),
          );
          break;
        case DrivePrivacy.private:
          final profile = _profileCubit.state;
          SecretKey? driveKey;

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
          final decodedBytes = await decryptTransactionData(
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
      addError(err);
    }
  }

  Future<void> emitAudioPreview(FileEntry file, String dataUrl) async {
    try {
      emit(const FsEntryPreviewLoading());

      final dataTx = await _arweave.getTransactionDetails(file.dataTxId);
      if (dataTx == null) {
        emit(FsEntryPreviewFailure());
        return;
      }

      final drive = await _driveDao.driveById(driveId: driveId).getSingle();
      switch (drive.privacy) {
        case DrivePrivacy.public:
          audioPlayer.pause();
          final duration = await audioPlayer.setUrl(
            // Load a URL
            dataUrl,
          );
          await audioPlayer.play();
          emit(FsEntryPreviewAudio(previewUrl: dataUrl));
          break;
        case DrivePrivacy.private:
          emit(FsEntryPreviewUnavailable());
          break;

        default:
          emit(FsEntryPreviewFailure());
      }
    } catch (err) {
      addError(err);
    }
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(FsEntryPreviewFailure());
    super.onError(error, stackTrace);

    print('Failed to load entity activity: $error $stackTrace');
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
        return true;
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
