import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'feedback_survey_state.dart';

class FeedbackSurveyCubit extends Cubit<FeedbackSurveyState> {
  FeedbackSurveyCubit(FeedbackSurveyState initialState) : super(initialState);
  bool hasAlreadyBeenOpenedFromSync = false;

  void openModal(String source) {
    if (!(hasAlreadyBeenOpenedFromSync && source == 'sync')) {
      emit(FeedbackSurveyOpen(source: source));
    }
    hasAlreadyBeenOpenedFromSync =
        hasAlreadyBeenOpenedFromSync || source == 'sync';
  }

  void closeModal() {
    emit(FeedbackSurveyClose());
  }

  void dontRemindMeAgain() {
    emit(FeedbackSurveyDontRemindMeAgain());
  }
}
