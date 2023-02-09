import 'package:ardrive/blocs/feedback_survey/feedback_survey_cubit.dart';
import 'package:ardrive/components/title_with_close_action.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/screen_sizes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> openFeedbackSurveyModal(BuildContext context) => showGeneralDialog(
      context: context,
      pageBuilder: (BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) {
        return const FeedbackSurveyModal();
      },
    );

class FeedbackSurveyModal extends StatelessWidget {
  const FeedbackSurveyModal({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<FeedbackSurveyCubit, FeedbackSurveyState>(
          builder: (context, state) {
        final deviceWidth = MediaQuery.of(context).size.width;
        final padding = deviceWidth <= kMaxMobileWidth
            ? const EdgeInsets.symmetric(horizontal: 24)
            : const EdgeInsets.only(bottom: 0, left: 0);
        final content = AlertDialog(
          insetPadding: padding,
          titlePadding: EdgeInsets.zero,
          title: TitleWithCloseAction(
            title: state is FeedbackSurveyDontRemindMe
                ? appLocalizationsOf(context).weWontRemindYou
                : appLocalizationsOf(context).feedbackTitle,
            onClose: context.read<FeedbackSurveyCubit>().closeRemindMe,
          ),
          content: SizedBox(
            width: kMediumDialogWidth,
            child: state is FeedbackSurveyDontRemindMe
                ? Text(appLocalizationsOf(context).weWontRemindYouDescription)
                : Text(appLocalizationsOf(context).feedbackContent),
          ),
          actions: [
            Center(
              child: Column(
                children: state is FeedbackSurveyDontRemindMe
                    ? [
                        ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(50), // NEW
                            ),
                            onPressed: () {
                              context
                                  .read<FeedbackSurveyCubit>()
                                  .closeDontRemindMe();
                            },
                            child: Text(appLocalizationsOf(context).gotIt))
                      ]
                    : [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50), // NEW
                          ),
                          onPressed: () async {
                            await openUrl(url: Resources.surveyFeedbackFormUrl);

                            context.read<FeedbackSurveyCubit>().leaveFeedback();
                          },
                          child: Text(
                            appLocalizationsOf(context).leaveFeedback,
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            minimumSize: const Size.fromHeight(50), // NEW
                          ),
                          onPressed: () {
                            context.read<FeedbackSurveyCubit>().dontRemindMe();
                          },
                          child: Text(
                            appLocalizationsOf(context).noThanks,
                            textWidthBasis: TextWidthBasis.parent,
                          ),
                        ),
                      ],
              ),
            )
          ],
        );

        return Stack(
          children: [
            deviceWidth <= kMaxMobileWidth
                ? Center(
                    child: content,
                  )
                : Positioned(right: 50, bottom: 50, child: content)
          ],
        );
      });
}
