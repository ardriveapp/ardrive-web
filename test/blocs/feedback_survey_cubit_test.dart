import 'package:ardrive/blocs/feedback_survey/feedback_survey_cubit.dart';
import 'package:ardrive/utils/key_value_store.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_utils/fakes.dart';

void main() {
  group('FeedbackSurveyCubit', () {
    late KeyValueStore store;
    late FeedbackSurveyCubit feedbackCubit;

    setUp(() async {
      registerFallbackValue(SyncStateFake());
      registerFallbackValue(ProfileStateFake());

      Map<String, Object> values = <String, Object>{};
      SharedPreferences.setMockInitialValues(values);
      final fakePrefs = await SharedPreferences.getInstance();
      store = await LocalKeyValueStore.getInstance(prefs: fakePrefs);

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
      'dismiss modal',
      build: () => feedbackCubit,
      act: (bloc) => bloc.closeRemindMe(),
      expect: () => [
        FeedbackSurveyRemindMe(isOpen: false),
      ],
    );

    blocTest<FeedbackSurveyCubit, FeedbackSurveyState>(
      'the modal will be opened again if reset was called',
      build: () => feedbackCubit,
      act: (bloc) async {
        bloc.reset();
        await bloc.openRemindMe();
      },
      expect: () => [FeedbackSurveyRemindMe(isOpen: true)],
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
      'no thanks! dont remind me again',
      build: () => feedbackCubit,
      act: (bloc) async => bloc.closeDontRemindMe(),
      expect: () => [
        FeedbackSurveyDontRemindMe(isOpen: false),
      ],
    );

    blocTest<FeedbackSurveyCubit, FeedbackSurveyState>(
      'won\'t open modal when the preference is set to false',
      build: () => feedbackCubit,
      act: (bloc) async => await bloc.openRemindMe(),
      expect: () => [],
    );
  });
}
