import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'activity_state.dart';

class ActivityCubit extends Cubit<ActivityState> {
  ActivityCubit() : super(ActivityNotRunning());

  /// Runs [activity] with [ActivityInProgress] held for its whole duration.
  ///
  /// Returns the future that completes when the activity has finished. It was
  /// declared `void` before, which read as "fire and forget" although an
  /// `async` function returns a future either way, so `showModalDialog`'s
  /// callers did in fact wait for the dialog to close. The type now says so.
  /// The `finally` is the one behaviour change: an activity that throws no
  /// longer leaves [ActivityInProgress] set for the rest of the session.
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
