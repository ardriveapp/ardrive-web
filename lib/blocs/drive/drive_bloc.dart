import 'package:bloc/bloc.dart';
import 'package:drive/models/drive.dart';
import 'drive_event.dart';
import 'drive_state.dart';

class DriveBloc extends Bloc<DriveEvent, DriveState> {
  DriveBloc()
      : super(DriveLoadSuccess([
          Drive(name: 'Personal'),
          Drive(name: 'Work'),
        ]));

  @override
  Stream<DriveState> mapEventToState(DriveEvent event) async* {
    if (event is DriveAddedEvent) yield* _mapAddDriveToState(event);
  }

  Stream<DriveState> _mapAddDriveToState(DriveAddedEvent event) async* {
    if (state is DriveLoadSuccess) {
      final List<Drive> updatedDrives =
          List.from((state as DriveLoadSuccess).drives)..add(event.drive);

      yield DriveLoadSuccess(updatedDrives);
      // write to repo
    }
  }
}
