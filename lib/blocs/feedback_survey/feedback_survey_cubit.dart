import 'package:ardrive/utils/key_value_store.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'feedback_survey_state.dart';

class FeedbackSurveyCubit extends Cubit<FeedbackSurveyState> {
  static const dontRemindMeAgainKey = 'dont_remind_me_again';
  late KeyValueStore _store;
  bool _hasAlreadyBeenOpened = false;

  FeedbackSurveyCubit(FeedbackSurveyState initialState, {KeyValueStore? store})
      : super(initialState) {
    _store = store ?? KeyValueStore();
  }

  Future<void> openRemindMe() async {
    await _store.setup();
    final dontRemindMeAgain = _store.getBool(dontRemindMeAgainKey);
    if (!(_hasAlreadyBeenOpened || dontRemindMeAgain)) {
      emit(FeedbackSurveyRemindMe(isOpen: true));
      _hasAlreadyBeenOpened = true;
    }
  }

  void closeRemindMe() {
    emit(FeedbackSurveyRemindMe(isOpen: false));
  }

  Future<void> leaveFeedback() async {
    await _store.setup();
    await _store.putBool(dontRemindMeAgainKey, true);
    emit(FeedbackSurveyDontRemindMe(isOpen: false));
  }

  void dontRemindMe() {
    emit(FeedbackSurveyDontRemindMe(isOpen: true));
  }

  Future<void> closeDontRemindMe() async {
    await _store.setup();
    await _store.putBool(dontRemindMeAgainKey, true);
    emit(FeedbackSurveyDontRemindMe(isOpen: false));
  }
}
