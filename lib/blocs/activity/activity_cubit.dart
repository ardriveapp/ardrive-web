import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
