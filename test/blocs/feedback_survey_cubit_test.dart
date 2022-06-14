import 'package:ardrive/blocs/feedback_survey/feedback_survey_cubit.dart';
import 'package:ardrive/utils/key_value_store.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_utils/fakes.dart';

void main() {
  group('FeedbackSurveyCubit', () {
    final store = KeyValueStore();
    late FeedbackSurveyCubit feedbackCubit;

    setUp(() async {
      registerFallbackValue(SyncStatefake());
      registerFallbackValue(ProfileStatefake());

      Map<String, Object> values = <String, Object>{};
      SharedPreferences.setMockInitialValues(values);
      final fakePrefs = await SharedPreferences.getInstance();
      await store.setup(instance: fakePrefs);

      feedbackCubit = FeedbackSurveyCubit(FeedbackSurveyInitialState());
    });

    blocTest<FeedbackSurveyCubit, FeedbackSurveyState>(
      'open modal',
      build: () => feedbackCubit,
      act: (bloc) async => await bloc.openRemindMe(),
      expect: () => [
        FeedbackSurveyRemindMe(isOpen: true),
      ],
    );

    blocTest<FeedbackSurveyCubit, FeedbackSurveyState>(
      'leave feedback',
      build: () => feedbackCubit,
      act: (bloc) async => await bloc.leaveFeedback(),
      expect: () => [
        FeedbackSurveyDontRemindMe(isOpen: false),
      ],
    );

    blocTest<FeedbackSurveyCubit, FeedbackSurveyState>(
      'dismiss modal',
      build: () => feedbackCubit,
      act: (bloc) => bloc.closeRemindMe(),
      expect: () => [
        FeedbackSurveyRemindMe(isOpen: false),
      ],
    );

    blocTest<FeedbackSurveyCubit, FeedbackSurveyState>(
      'no thanks! dont remind me again',
      build: () => feedbackCubit,
      act: (bloc) async => await bloc.closeDontRemindMe(),
      expect: () => [
        FeedbackSurveyDontRemindMe(isOpen: false),
      ],
    );
  });

  group('FeedbackSurveyCubit preferences', () {
    final store = KeyValueStore();
    late FeedbackSurveyCubit feedbackCubit;

    setUp(() async {
      registerFallbackValue(SyncStatefake());
      registerFallbackValue(ProfileStatefake());

      Map<String, Object> values = <String, Object>{
        FeedbackSurveyCubit.dontRemindMeAgainKey: true
      };
      SharedPreferences.setMockInitialValues(values);
      final fakePrefs = await SharedPreferences.getInstance();
      await store.setup(instance: fakePrefs);

      feedbackCubit =
          FeedbackSurveyCubit(FeedbackSurveyInitialState(), store: store);
    });

    blocTest<FeedbackSurveyCubit, FeedbackSurveyState>(
      'won\'t open modal when set',
      build: () => feedbackCubit,
      act: (bloc) async => await bloc.openRemindMe(),
      expect: () => [],
    );
  });
}
