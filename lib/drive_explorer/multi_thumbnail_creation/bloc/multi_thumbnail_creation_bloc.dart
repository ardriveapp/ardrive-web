import 'package:ardrive/core/arfs/repository/drive_repository.dart';
import 'package:ardrive/drive_explorer/thumbnail/repository/thumbnail_repository.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/utils/constants.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'multi_thumbnail_creation_event.dart';
part 'multi_thumbnail_creation_state.dart';

class MultiThumbnailCreationBloc
    extends Bloc<MultiThumbnailCreationEvent, MultiThumbnailCreationState> {
  final DriveRepository _driveRepository;
  final ThumbnailRepository _thumbnailRepository;

  bool _isCancelled = false;

  MultiThumbnailCreationBloc({
    required DriveRepository driveRepository,
    required ThumbnailRepository thumbnailRepository,
  })  : _thumbnailRepository = thumbnailRepository,
        _driveRepository = driveRepository,
        super(MultiThumbnailCreationInitial()) {
    on<MultiThumbnailCreationEvent>((event, emit) async {
      if (event is CreateMultiThumbnailForDrive) {
        await _createMultiThumbnailForDrive(event, emit);
      }
      if (event is CancelMultiThumbnailCreation) {
        _isCancelled = true;
        emit(MultiThumbnailCreationCancelled());
      }
    });
  }

  List<ThumbnailLoadingStatus> _thumbnails = [];

  Future<void> _createMultiThumbnailForDrive(
    CreateMultiThumbnailForDrive event,
    Emitter<MultiThumbnailCreationState> emit,
  ) async {
    emit(MultiThumbnailCreationLoadingFiles());

    final files = await _driveRepository.getAllFileEntriesInDrive(
      driveId: event.drive.id,
    );

    final images = files.where((element) =>
        (element.thumbnail == null || element.thumbnail == 'null') &&
        supportedImageTypesInFilePreview
            .contains(element.dataContentType ?? ''));

    if (images.isEmpty) {
      emit(MultiThumbnailCreationFilesLoadedEmpty());
      return;
    }

    emit(MultiThumbnailCreationFilesLoaded(files: files));

    _thumbnails = images
        .map((file) => ThumbnailLoadingStatus(
              file: file,
              loaded: false,
            ))
        .toList();

    emit(MultiThumbnailCreationLoadingThumbnails(
      thumbnails: _thumbnails,
    ));

    for (final thumbnail in _thumbnails) {
      if (_isCancelled) {
        return;
      }

      try {
        await _thumbnailRepository.uploadThumbnail(
          fileId: thumbnail.file.id,
        );

        final index = _thumbnails
            .indexWhere((element) => element.file.id == thumbnail.file.id);

        _thumbnails[index] = ThumbnailLoadingStatus(
          file: thumbnail.file,
          loaded: true,
        );

        emit(MultiThumbnailCreationLoadingThumbnails(
          thumbnails: _thumbnails,
        ));
      } catch (e) {
        logger.e('Error uploading thumbnail', e);
      }
    }

    emit(MultiThumbnailCreationThumbnailsLoaded());
  }

  @override
  Future<void> close() {
    _isCancelled = true;
    return super.close();
  }
}
