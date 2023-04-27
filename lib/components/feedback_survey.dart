import 'package:ardrive/blocs/feedback_survey/feedback_survey_cubit.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/screen_sizes.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> openFeedbackSurveyModal(BuildContext context) =>
    showAnimatedDialog(
      context,
      content: const FeedbackSurveyModal(),
    );

class FeedbackSurveyModal extends StatelessWidget {
  const FeedbackSurveyModal({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<FeedbackSurveyCubit, FeedbackSurveyState>(
        builder: (context, state) {
          final deviceWidth = MediaQuery.of(context).size.width;
          final content = ArDriveStandardModal(
            hasCloseButton: true,
            title: state is FeedbackSurveyDontRemindMe
                ? appLocalizationsOf(context).weWontRemindYou
                : appLocalizationsOf(context).feedbackTitle,
            content: Column(
              children: [
                SizedBox(
                  width: kMediumDialogWidth,
                  child: state is FeedbackSurveyDontRemindMe
                      ? Text(
                          appLocalizationsOf(context)
                              .weWontRemindYouDescription,
                          style: ArDriveTypography.body.buttonNormalRegular(),
                        )
                      : Text(
                          appLocalizationsOf(context).feedbackContent,
                          style: ArDriveTypography.body.buttonNormalRegular(),
                        ),
                ),
                const SizedBox(
                  height: 32,
                ),
                if (state is FeedbackSurveyDontRemindMe)
                  ArDriveButton(
                    maxWidth: kMediumDialogWidth,
                    onPressed: () {
                      context.read<FeedbackSurveyCubit>().closeDontRemindMe();
                    },
                    text: appLocalizationsOf(context).gotIt,
                  )
                else
                  Column(
                    children: [
                      ArDriveButton(
                        maxWidth: kMediumDialogWidth,
                        onPressed: () async {
                          await openUrl(url: Resources.surveyFeedbackFormUrl);

                          // ignore: use_build_context_synchronously
                          context.read<FeedbackSurveyCubit>().leaveFeedback();
                        },
                        text: appLocalizationsOf(context).leaveFeedback,
                      ),
                      const SizedBox(
                        height: 8,
                      ),
                      ArDriveButton(
                        style: ArDriveButtonStyle.tertiary,
                        onPressed: () {
                          context.read<FeedbackSurveyCubit>().dontRemindMe();
                        },
                        text: appLocalizationsOf(context).noThanks,
                      ),
                    ],
                  ),
              ],
            ),
          );

          return Stack(
            children: [
              deviceWidth <= kMaxMobileWidth
                  ? Center(
                      child: content,
                    )
                  : Positioned(
                      right: 50,
                      bottom: 50,
                      child: content,
                    )
            ],
          );
        },
      );
}
