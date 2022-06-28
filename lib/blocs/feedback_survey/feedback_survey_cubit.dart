import 'package:ardrive/utils/key_value_store.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'feedback_survey_state.dart';

class FeedbackSurveyCubit extends Cubit<FeedbackSurveyState> {
  static const dontRemindMeAgainKey = 'dont_remind_me_again';
  static KeyValueStore? _maybeStore;
  bool _hasAlreadyBeenOpened = false;

  FeedbackSurveyCubit(
    FeedbackSurveyState initialState, {

    /// takes a KeyValueStore for testing purposes
    KeyValueStore? store,
  }) : super(initialState) {
    _maybeStore ??= store;
  }

  Future<KeyValueStore> get _store async {
    /// lazily initialize KeyValueStore
    _maybeStore ??= await LocalKeyValueStore.getInstance();
    return _maybeStore!;
  }

  Future<void> openRemindMe() async {
    final dontRemindMeAgain =
        (await _store).getBool(dontRemindMeAgainKey) == true;
    if (!(_hasAlreadyBeenOpened || dontRemindMeAgain)) {
      emit(FeedbackSurveyRemindMe(isOpen: true));
      _hasAlreadyBeenOpened = true;
    }
  }

  void closeRemindMe() {
    emit(FeedbackSurveyRemindMe(isOpen: false));
  }

  Future<void> leaveFeedback() async {
    await (await _store).putBool(dontRemindMeAgainKey, true);
    emit(FeedbackSurveyDontRemindMe(isOpen: false));
  }

  Future<void> dontRemindMe() async {
    await (await _store).putBool(dontRemindMeAgainKey, true);
    emit(FeedbackSurveyDontRemindMe(isOpen: true));
  }

  void closeDontRemindMe() {
    emit(FeedbackSurveyDontRemindMe(isOpen: false));
  }
}
