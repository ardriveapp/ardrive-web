part of 'feedback_survey_cubit.dart';

abstract class FeedbackSurveyState extends Equatable {}

class FeedbackSurveyRemindMe extends FeedbackSurveyState {
  final bool isOpen;
  final String source;

  FeedbackSurveyRemindMe({required this.isOpen, required this.source})
      : super();

  @override
  List<Object?> get props => [isOpen, source];
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
