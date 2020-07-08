import 'package:bloc/bloc.dart';
import 'package:drive/repositories/repositories.dart';

part 'drives_event.dart';
part 'drives_state.dart';

class DrivesBloc extends Bloc<DrivesEvent, DrivesState> {
  DrivesBloc()
      : super(DrivesLoadSuccess([
          Drive(name: 'Personal'),
          Drive(name: 'Work'),
        ]));

  @override
  Stream<DrivesState> mapEventToState(DrivesEvent event) async* {
    if (event is DriveAdded) yield* _mapAddDriveToState(event);
  }

  Stream<DrivesState> _mapAddDriveToState(DriveAdded event) async* {
    if (state is DrivesLoadSuccess) {
      final List<Drive> updatedDrives =
          List.from((state as DrivesLoadSuccess).drives)..add(event.drive);

      yield DrivesLoadSuccess(updatedDrives);
      // write to repo
    }
  }
}
