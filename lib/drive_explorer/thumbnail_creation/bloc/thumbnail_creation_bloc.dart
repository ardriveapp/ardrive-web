import 'package:ardrive/drive_explorer/thumbnail/repository/thumbnail_repository.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'thumbnail_creation_event.dart';
part 'thumbnail_creation_state.dart';

class ThumbnailCreationBloc
    extends Bloc<ThumbnailCreationEvent, ThumbnailCreationState> {
  final ThumbnailRepository _thumbnailRepository;

  ThumbnailCreationBloc({
    required ThumbnailRepository thumbnailRepository,
  })  : _thumbnailRepository = thumbnailRepository,
        super(
          ThumbnailCreationInitial(),
        ) {
    on<ThumbnailCreationEvent>((event, emit) async {
      if (state is ThumbnailCreationLoading) return;

      emit(ThumbnailCreationLoading());

      try {
        (event as CreateThumbnail);

        await _thumbnailRepository.uploadThumbnail(
            fileId: event.fileDataTableItem.id);

        emit(ThumbnailCreationSuccess());
      } catch (e, stackTrace) {
        logger.e('Error uploading thumbnail', e, stackTrace);
        emit(ThumbnailCreationError());
      }
    });
  }
}
