import 'dart:async';

import 'package:ardrive/blocs/drive_detail/selected_item.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:mime/mime.dart';

part 'fs_entry_preview_state.dart';

class FsEntryPreviewCubit extends Cubit<FsEntryPreviewState> {
  final String driveId;
  final SelectedItem? maybeSelectedItem;

  final DriveDao _driveDao;
  final AppConfig _config;

  StreamSubscription? _entrySubscription;

  final previewMaxFileSize = 1024 * 1024 * 10;
  final allowedPreviewContentTypes = [];

  FsEntryPreviewCubit({
    required this.driveId,
    this.maybeSelectedItem,
    required DriveDao driveDao,
    required AppConfig config,
  })  : _driveDao = driveDao,
        _config = config,
        super(FsEntryPreviewInitial()) {
    final selectedItem = maybeSelectedItem;
    if (selectedItem != null) {
      switch (selectedItem.runtimeType) {
        case SelectedFile:
          _entrySubscription = _driveDao
              .fileById(driveId: driveId, fileId: selectedItem.id)
              .watchSingle()
              .listen((file) {
            if (file.size <= previewMaxFileSize) {
              final contentType =
                  file.dataContentType ?? lookupMimeType(file.name);
              final previewType = contentType?.split('/').first;
              final previewUrl =
                  '${_config.defaultArweaveGatewayUrl}/${file.dataTxId}';
              switch (previewType) {
                case 'image':
                  emit(FsEntryPreviewImage(previewUrl: previewUrl));
                  break;
                case 'audio':
                  emit(FsEntryPreviewAudio(previewUrl: previewUrl));
                  break;
                case 'video':
                  emit(FsEntryPreviewVideo(previewUrl: previewUrl));
                  break;
                case 'text':
                  emit(FsEntryPreviewText(previewUrl: previewUrl));
                  break;
                default:
              }
            } else {
              emit(FsEntryPreviewUnavailable());
            }
          });
          break;

        default:
      }
    } else {
      emit(FsEntryPreviewUnavailable());
    }
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(FsEntryPreviewFailure());
    super.onError(error, stackTrace);

    print('Failed to load entity activity: $error $stackTrace');
  }

  @override
  Future<void> close() {
    _entrySubscription?.cancel();
    return super.close();
  }
}
