import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'feedback_survey_state.dart';

class FeedbackSurveyCubit extends Cubit<FeedbackSurveyState> {
  bool hasAlreadyBeenOpened = false;

  FeedbackSurveyCubit(FeedbackSurveyState initialState) : super(initialState);

  void openRemindMe() {
    if (!(hasAlreadyBeenOpened)) {
      emit(FeedbackSurveyRemindMe(isOpen: true));
    }
    hasAlreadyBeenOpened = true;
  }

  void closeRemindMe() {
    emit(FeedbackSurveyRemindMe(isOpen: false));
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
