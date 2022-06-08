import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'feedback_survey_state.dart';

class FeedbackSurveyCubit extends Cubit<FeedbackSurveyState> {
  FeedbackSurveyCubit(FeedbackSurveyState initialState) : super(initialState);
  bool hasAlreadyBeenOpenedFromSync = false;

  void openModal(String source) {
    if (!(hasAlreadyBeenOpenedFromSync && source == 'sync')) {
      emit(FeedbackSurveyRemindMe(isOpen: true, source: source));
    }
    hasAlreadyBeenOpenedFromSync =
        hasAlreadyBeenOpenedFromSync || source == 'sync';
  }

  void closeModal(String source) {
    emit(FeedbackSurveyRemindMe(isOpen: false, source: source));
  }

  void leaveFeedback() {
    emit(FeedbackSurveyDontRemindMe(isOpen: false));
  }

  void dontRemindMeAgain() {
    emit(FeedbackSurveyDontRemindMe(isOpen: true));
  }

  void dontRemindMeAgainClose() {
    emit(FeedbackSurveyDontRemindMe(isOpen: false));
  }
}
