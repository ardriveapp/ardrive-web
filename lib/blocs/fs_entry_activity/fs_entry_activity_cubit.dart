import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

part 'fs_entry_activity_state.dart';

class FsEntryActivityCubit extends Cubit<FsEntryActivityState> {
  FsEntryActivityCubit() : super(FsEntryActivityInitial());
}
