import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'feedback_survey_state.dart';

class FeedbackSurveyCubit extends Cubit<FeedbackSurveyState> {
  FeedbackSurveyCubit(FeedbackSurveyState initialState) : super(initialState);

  void openModal() {
    emit(FeedbackSurveyOpen());
  }

  void closeModal() {
    emit(FeedbackSurveyClose());
  }

  void dontRemindMeAgain() {
    emit(FeedbackSurveyDontRemindMeAgain());
  }
}
