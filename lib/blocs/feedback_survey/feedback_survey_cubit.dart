import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'feedback_survey_state.dart';

class FeedbackSurveyCubit extends Cubit<FeedbackSurveyState> {
  FeedbackSurveyCubit(FeedbackSurveyState initialState) : super(initialState);
  bool hasAlreadyBeenOpenedFromSync = false;

  void openRemindMe(String source) {
    if (!(hasAlreadyBeenOpenedFromSync && source == 'sync')) {
      emit(FeedbackSurveyRemindMe(isOpen: true, source: source));
    }
    hasAlreadyBeenOpenedFromSync =
        hasAlreadyBeenOpenedFromSync || source == 'sync';
  }

  void closeRemindMe(String source) {
    emit(FeedbackSurveyRemindMe(isOpen: false, source: source));
  }

  void leaveFeedback() {
    emit(FeedbackSurveyDontRemindMe(isOpen: false));
  }

  void dontRemindMe() {
    emit(FeedbackSurveyDontRemindMe(isOpen: true));
  }

  void closeDontRemindMe() {
    emit(FeedbackSurveyDontRemindMe(isOpen: false));
  }
}
