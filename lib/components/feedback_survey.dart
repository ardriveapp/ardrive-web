import 'package:ardrive/blocs/feedback_survey/feedback_survey_cubit.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/launch_survey_url.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> openFeedbackSurveyModal(BuildContext context) => showGeneralDialog(
      context: context,
      pageBuilder: (BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) {
        return const Align(
          alignment: Alignment.bottomRight,
          child: FeedbackSurveyModal(),
        );
      },
    );

class FeedbackSurveyModal extends StatelessWidget {
  const FeedbackSurveyModal({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<FeedbackSurveyCubit, FeedbackSurveyState>(
        builder: (context, state) => Stack(
          children: [
            Positioned(
              right: 50,
              bottom: 50,
              child: AlertDialog(
                insetPadding: const EdgeInsets.only(bottom: 0, left: 0),
                titlePadding: EdgeInsets.zero,
                title: Container(
                    color: kDarkSurfaceColor,
                    height: 72,
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              onPressed: () => context
                                  .read<FeedbackSurveyCubit>()
                                  .closeRemindMe(),
                              icon: const Icon(Icons.close),
                              color: kOnDarkSurfaceMediumEmphasis,
                              iconSize: 16,
                              visualDensity: const VisualDensity(
                                  horizontal: -4, vertical: -4),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(
                              bottom: 12, right: 18, left: 18),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                state is FeedbackSurveyDontRemindMe
                                    ? Text(
                                        appLocalizationsOf(context)
                                            .weWontRemindYou,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headline6!
                                            .copyWith(
                                                color:
                                                    kOnDarkSurfaceHighEmphasis),
                                      )
                                    : Text(
                                        appLocalizationsOf(context)
                                            .feedbackTitle,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headline6!
                                            .copyWith(
                                                color:
                                                    kOnDarkSurfaceHighEmphasis),
                                      ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )),
                content: SizedBox(
                  width: kMediumDialogWidth,
                  child: state is FeedbackSurveyDontRemindMe
                      ? Text(appLocalizationsOf(context)
                          .weWontRemindYouDescription)
                      : Text(appLocalizationsOf(context).feedbackContent),
                ),
                actions: [
                  Center(
                    child: Column(
                      children: state is FeedbackSurveyDontRemindMe
                          ? [
                              ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    minimumSize:
                                        const Size.fromHeight(50), // NEW
                                  ),
                                  onPressed: () {
                                    context
                                        .read<FeedbackSurveyCubit>()
                                        .closeDontRemindMe();
                                  },
                                  child:
                                      Text(appLocalizationsOf(context).gotIt))
                            ]
                          : [
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(50), // NEW
                                ),
                                onPressed: () {
                                  launchSurveyURL();
                                  context
                                      .read<FeedbackSurveyCubit>()
                                      .leaveFeedback();
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
                                  context
                                      .read<FeedbackSurveyCubit>()
                                      .dontRemindMe();
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
              ),
            )
          ],
        ),
      );
}
