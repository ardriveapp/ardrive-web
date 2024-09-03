import 'package:ardrive/drive_explorer/thumbnail/repository/thumbnail_repository.dart';
import 'package:ardrive/drive_explorer/thumbnail/thumbnail.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'thumbnail_event.dart';
part 'thumbnail_state.dart';

class ThumbnailBloc extends Bloc<ThumbnailEvent, ThumbnailState> {
  final ThumbnailRepository _thumbnailRepository;

  ThumbnailBloc({
    required ThumbnailRepository thumbnailRepository,
  })  : _thumbnailRepository = thumbnailRepository,
        super(ThumbnailInitial()) {
    on<GetThumbnail>((event, emit) async {
      emit(ThumbnailLoading());

      try {
        final thumbnail = await _thumbnailRepository.getThumbnail(
          fileDataTableItem: event.fileDataTableItem,
        );

        emit(ThumbnailLoaded(thumbnail: thumbnail));
      } catch (e) {
        emit(ThumbnailError());
      }
    });
  }
}
