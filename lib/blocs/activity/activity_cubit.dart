import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'activity_state.dart';

class ActivityCubit extends Cubit<ActivityState> {
  ActivityCubit() : super(ActivityNotRunning());

  /// Runs [activity] with [ActivityInProgress] held for its whole duration,
  /// and completes when it has finished. An activity that throws still
  /// releases [ActivityInProgress].
  Future<void> performUninterruptableActivity(Function activity) async {
    if (state is ActivityInProgress) {
      throw ActivityAlreadyInProgressError();
    }
    emit(ActivityInProgress());
    try {
      await activity();
    } finally {
      emit(ActivityNotRunning());
    }
  }
}

class ActivityAlreadyInProgressError extends Error {}
