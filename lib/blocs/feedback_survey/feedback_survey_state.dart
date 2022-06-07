part of 'feedback_survey_cubit.dart';

abstract class FeedbackSurveyState extends Equatable {}

class FeedbackSurveyOpen extends FeedbackSurveyState {
  final String source;

  FeedbackSurveyOpen({required this.source}) : super();

  @override
  List<Object?> get props => [source];
}

class FeedbackSurveyClose extends FeedbackSurveyState {
  @override
  List<Object?> get props => [];
}

class FeedbackSurveyDontRemindMeAgain extends FeedbackSurveyState {
  @override
  List<Object?> get props => [];
}

class FeedbackSurveyInitialState extends FeedbackSurveyState {
  @override
  List<Object?> get props => [];
}
