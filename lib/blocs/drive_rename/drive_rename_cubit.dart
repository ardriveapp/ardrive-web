import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

part 'drive_rename_state.dart';

class DriveRenameCubit extends Cubit<DriveRenameState> {
  DriveRenameCubit() : super(DriveRenameInitial());
}
