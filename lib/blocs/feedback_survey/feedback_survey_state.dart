part of 'feedback_survey_cubit.dart';

abstract class FeedbackSurveyState extends Equatable {}

class FeedbackSurveyRemindMe extends FeedbackSurveyState {
  final bool isOpen;

  FeedbackSurveyRemindMe({required this.isOpen}) : super();

  @override
  List<Object?> get props => [isOpen];
}

class FeedbackSurveyDontRemindMe extends FeedbackSurveyState {
  final bool isOpen;

  FeedbackSurveyDontRemindMe({required this.isOpen}) : super();

  @override
  List<Object?> get props => [isOpen];
}

class FeedbackSurveyInitialState extends FeedbackSurveyState {
  @override
  List<Object?> get props => [];
}
