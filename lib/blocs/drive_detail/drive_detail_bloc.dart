import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';

part 'drive_detail_event.dart';
part 'drive_detail_state.dart';

class DriveDetailBloc extends Bloc<DriveDetailEvent, DriveDetailState> {
  DriveDetailBloc() : super(DriveDetailLoadSuccess('123'));

  @override
  Stream<DriveDetailState> mapEventToState(
    DriveDetailEvent event,
  ) async* {
    if (event is OpenedFolder) yield DriveDetailLoadSuccess(event.folderId);
  }
}
