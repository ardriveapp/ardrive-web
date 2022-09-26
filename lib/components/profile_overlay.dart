import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ProfileOverlay extends StatelessWidget {
  const ProfileOverlay({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Card(
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kMediumDialogWidth),
                child: BlocBuilder<ProfileCubit, ProfileState>(
                  builder: (context, state) => state is ProfileLoggedIn
                      ? ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(state.username!),
                          subtitle: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                state.walletAddress,
                                style: Theme.of(context).textTheme.bodyText2,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${double.tryParse(utils.winstonToAr(state.walletBalance))?.toStringAsFixed(5) ?? 0} AR',
                                style: Theme.of(context)
                                    .textTheme
                                    .headline6!
                                    .copyWith(
                                      color: kPrimarySwatch,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(
                                width: 32,
                                height: 32,
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                  minimumSize: Size.zero,
                                  padding: const EdgeInsets.only(left: 0.0),
                                  textStyle: const TextStyle(
                                    decoration: TextDecoration.underline,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                onPressed: () => openUrl(
                                    url: Resources.surveyFeedbackFormUrl),
                                child: Text(
                                  appLocalizationsOf(context).leaveFeedback,
                                ),
                              ),
                            ],
                          ),
                          trailing: IconButton(
                              icon: const Icon(Icons.logout),
                              tooltip: appLocalizationsOf(context).logout,
                              onPressed: () {
                                context.read<ProfileCubit>().logoutProfile();
                              }),
                        )
                      : ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(appLocalizationsOf(context).notLoggedIn),
                          subtitle: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(appLocalizationsOf(context)
                                  .logInToExperienceFeatures),
                              const SizedBox(
                                width: 32,
                                height: 32,
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                  minimumSize: Size.zero,
                                  padding: const EdgeInsets.only(left: 0.0),
                                  textStyle: const TextStyle(
                                    decoration: TextDecoration.underline,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                onPressed: () => openUrl(
                                    url: Resources.surveyFeedbackFormUrl),
                                child: Text(
                                  appLocalizationsOf(context).leaveFeedback,
                                ),
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.login),
                            tooltip: appLocalizationsOf(context).login,
                            onPressed: () => openUrl(
                              url: '/',
                              webOnlyWindowName: '_self',
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      );
}
