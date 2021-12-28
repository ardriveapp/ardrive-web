import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

part 'activity_state.dart';

class ActivityCubit extends Cubit<ActivityState> {
  ActivityCubit() : super(ActivityNotRunning());

  void performUninterruptableActivity(Function activity) async {
    if (state is ActivityInProgress) {
      throw ActivityAlreadyInProgressError();
    }
    emit(ActivityInProgress());
    await activity();
    emit(ActivityNotRunning());
  }
}

class ActivityAlreadyInProgressError extends Error {}
