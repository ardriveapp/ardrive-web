import 'package:ardrive/core/arfs/repository/drive_repository.dart';
import 'package:ardrive/drive_explorer/thumbnail/repository/thumbnail_repository.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/utils/constants.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'multi_thumbnail_creation_event.dart';
part 'multi_thumbnail_creation_state.dart';

class MultiThumbnailCreationBloc
    extends Bloc<MultiThumbnailCreationEvent, MultiThumbnailCreationState> {
  final DriveRepository _driveRepository;
  final ThumbnailRepository _thumbnailRepository;

  WorkerPool<ThumbnailLoadingStatus>? _worker;

  bool _inExecution = false;

  final List<String> _skippedDrives = [];

  MultiThumbnailCreationBloc({
    required DriveRepository driveRepository,
    required ThumbnailRepository thumbnailRepository,
  })  : _thumbnailRepository = thumbnailRepository,
        _driveRepository = driveRepository,
        super(MultiThumbnailCreationInitial()) {
    on<MultiThumbnailCreationEvent>((event, emit) async {
      if (event is CreateMultiThumbnailForAllDrives) {
        _worker = null;
        await _createMultiThumbnailForDrive(event, emit);
      }

      if (event is SkipDriveMultiThumbnailCreation) {
        _skippedDrives.add((state as MultiThumbnailCreationLoadingThumbnails)
            .driveInExecution!
            .id);
        _worker?.cancel();
      }

      if (event is CloseMultiThumbnailCreation) {
        emit(MultiThumbnailClosingModal());
      }

      if (event is CancelMultiThumbnailCreation) {
        _worker?.cancel();
        emit(MultiThumbnailCreationCancelled());
        _inExecution = false;
      }
    });
  }

  List<ThumbnailLoadingStatus> _thumbnails = [];

  Future<void> _createMultiThumbnailForDrive(
    CreateMultiThumbnailForAllDrives event,
    Emitter<MultiThumbnailCreationState> emit,
  ) async {
    try {
      if (_inExecution) {
        return;
      }

      _inExecution = true;

      emit(MultiThumbnailCreationLoadingFiles());

      final userDrives = await _driveRepository.getAllUserDrives();

      if (userDrives.isEmpty) {
        emit(MultiThumbnailCreationFilesLoadedEmpty());
        return;
      }

      int loadedDrives = 0;
      bool noMissingThumbnails = true;

      _verifyCancelAndEmitLoadingState(
        state: MultiThumbnailCreationLoadingThumbnails(
          thumbnailsInDrive: _thumbnails,
          loadedDrives: loadedDrives,
          loadedThumbnailsInDrive: 0,
          numberOfDrives: userDrives.length,
          driveInExecution: userDrives.first,
        ),
        emit: emit,
      );

      for (final drive in userDrives) {
        final files = await _driveRepository.getAllFileEntriesInDrive(
          driveId: drive.id,
        );

        final images = files.where((element) =>
            (element.thumbnail == null || element.thumbnail == 'null') &&
            supportedImageTypesInFilePreview
                .contains(element.dataContentType ?? ''));

        logger.d('Images missing thumbnails: ${images.length}');

        if (images.isEmpty) {
          loadedDrives++;
          continue;
        }

        noMissingThumbnails = false;

        _thumbnails = images
            .map((file) => ThumbnailLoadingStatus(
                  file: file,
                  loaded: false,
                ))
            .toList();

        logger.d('Thumbnails to create: ${_thumbnails.length}');

        _verifyCancelAndEmitLoadingState(
          state: MultiThumbnailCreationLoadingThumbnails(
            thumbnailsInDrive: _thumbnails,
            driveInExecution: drive,
            loadedDrives: loadedDrives,
            loadedThumbnailsInDrive: 0,
            numberOfDrives: userDrives.length,
          ),
          emit: emit,
        );

        int loadedCount = 0;

        _worker = WorkerPool<ThumbnailLoadingStatus>(
          numWorkers: drive.isPrivate ? 1 : 2,
          maxTasksPerWorker: 2,
          taskQueue: List.from(_thumbnails),
          execute: (thumbnail) async {
            await _thumbnailRepository.uploadThumbnail(
              fileId: thumbnail.file.id,
            );

            loadedCount++;

            logger.d('Thumbnail created for file ${thumbnail.file.id}');

            final index = _thumbnails
                .indexWhere((element) => element.file.id == thumbnail.file.id);

            _thumbnails[index] = ThumbnailLoadingStatus(
              file: thumbnail.file,
              loaded: true,
            );

            _verifyCancelAndEmitLoadingState(
              state: MultiThumbnailCreationLoadingThumbnails(
                thumbnailsInDrive: _thumbnails,
                driveInExecution: drive,
                loadedDrives: loadedDrives,
                loadedThumbnailsInDrive: loadedCount,
                numberOfDrives: userDrives.length,
              ),
              emit: emit,
            );
          },
          onWorkerError: (thumbnail) {
            logger.d('Error creating thumbnail for file ${thumbnail.file.id}');
          },
        );

        await _worker?.onAllTasksCompleted;

        loadedDrives++;
      }

      _inExecution = false;

      if (noMissingThumbnails) {
        emit(MultiThumbnailCreationFilesLoadedEmpty());
        return;
      }

      emit(MultiThumbnailCreationThumbnailsLoaded());
    } catch (e) {
      if (e is ThumbnailCreationCanceledException) {
        logger.d('Thumbnail creation cancelled');
        return;
      }
      logger.e('Error creating thumbnails: $e');

      emit(MultiThumbnailCreationError());
    }

    _skippedDrives.clear();
  }

  void _verifyCancelAndEmitLoadingState({
    required MultiThumbnailCreationState state,
    required Emitter<MultiThumbnailCreationState> emit,
  }) {
    if (this.state is MultiThumbnailCreationCancelled) {
      throw ThumbnailCreationCanceledException();
    }

    if (state is MultiThumbnailCreationLoadingThumbnails &&
        state.driveInExecution != null &&
        _skippedDrives.contains(state.driveInExecution?.id)) {
      return;
    }
    if (!emit.isDone) emit(state);
  }

  @override
  Future<void> close() {
    _worker?.cancel();
    return super.close();
  }
}

class ThumbnailCreationCanceledException implements Exception {}
