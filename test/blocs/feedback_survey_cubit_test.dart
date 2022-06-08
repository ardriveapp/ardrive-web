import 'package:ardrive/blocs/feedback_survey/feedback_survey_cubit.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/fakes.dart';

void main() {
  group('FeedbackSurveyCubit', () {
    late FeedbackSurveyCubit feedbackCubit;
    const String testSource = 'test source';
    const String syncSource = 'test source';

    setUp(() {
      registerFallbackValue(SyncStatefake());
      registerFallbackValue(ProfileStatefake());
      feedbackCubit = FeedbackSurveyCubit(FeedbackSurveyInitialState());
    });

    tearDown(() async {});

    blocTest<FeedbackSurveyCubit, FeedbackSurveyState>(
      'open from sync first time',
      build: () => feedbackCubit,
      act: (bloc) async {
        bloc.openRemindMe(syncSource);
      },
      expect: () => [
        FeedbackSurveyRemindMe(isOpen: true, source: testSource),
      ],
    );

    blocTest<FeedbackSurveyCubit, FeedbackSurveyState>(
      'open modal',
      build: () => feedbackCubit,
      act: (bloc) async {
        bloc.openRemindMe(testSource);
      },
      expect: () => [
        FeedbackSurveyRemindMe(isOpen: true, source: testSource),
      ],
    );

    blocTest<FeedbackSurveyCubit, FeedbackSurveyState>(
      'open from sync second time',
      build: () => feedbackCubit,
      act: (bloc) async {
        bloc.openRemindMe(syncSource);
      },
      expect: () => [
        FeedbackSurveyRemindMe(isOpen: true, source: testSource),
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
        bloc.closeRemindMe(testSource);
      },
      expect: () => [
        FeedbackSurveyRemindMe(isOpen: false, source: testSource),
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
