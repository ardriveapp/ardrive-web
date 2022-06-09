import 'package:ardrive/blocs/feedback_survey/feedback_survey_cubit.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/fakes.dart';

void main() {
  group('FeedbackSurveyCubit', () {
    late FeedbackSurveyCubit feedbackCubit;

    setUp(() {
      registerFallbackValue(SyncStatefake());
      registerFallbackValue(ProfileStatefake());
      feedbackCubit = FeedbackSurveyCubit(FeedbackSurveyInitialState());
    });

    tearDown(() async {});

    blocTest<FeedbackSurveyCubit, FeedbackSurveyState>(
      'open modal',
      build: () => feedbackCubit,
      act: (bloc) async {
        bloc.openRemindMe();
      },
      expect: () => [
        FeedbackSurveyRemindMe(isOpen: true),
      ],
    );

    blocTest<FeedbackSurveyCubit, FeedbackSurveyState>(
      'leave feedback',
      build: () => feedbackCubit,
      act: (bloc) async {
        bloc.leaveFeedback();
      },
      expect: () => [
        FeedbackSurveyDontRemindMe(isOpen: false),
      ],
    );

    blocTest<FeedbackSurveyCubit, FeedbackSurveyState>(
      'dismiss modal',
      build: () => feedbackCubit,
      act: (bloc) async {
        bloc.closeRemindMe();
      },
      expect: () => [
        FeedbackSurveyRemindMe(isOpen: false),
      ],
    );

    blocTest<FeedbackSurveyCubit, FeedbackSurveyState>(
      'no thanks! dont remind me again',
      build: () => feedbackCubit,
      act: (bloc) async {
        bloc.closeDontRemindMe();
      },
      expect: () => [
        FeedbackSurveyDontRemindMe(isOpen: false),
      ],
    );
  });
}
