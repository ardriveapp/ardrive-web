import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

import '../../../services/analytics/ardrive_analytics.dart';
import 'profile_auth_fail_screen.dart';
import 'profile_auth_shell.dart';

class ProfileAuthUnlockScreen extends StatefulWidget {
  const ProfileAuthUnlockScreen({Key? key}) : super(key: key);

  @override
  ProfileAuthUnlockScreenState createState() => ProfileAuthUnlockScreenState();
}

class ProfileAuthUnlockScreenState extends State<ProfileAuthUnlockScreen> {
  @override
  Widget build(BuildContext context) => BlocProvider<ProfileUnlockCubit>(
        create: (context) => ProfileUnlockCubit(
          profileCubit: context.read<ProfileCubit>(),
          profileDao: context.read<ProfileDao>(),
          arweave: context.read<ArweaveService>(),
        ),
        child: BlocBuilder<ProfileUnlockCubit, ProfileUnlockState>(
          builder: (context, state) {
            if (state is ProfileUnlockFailure) {
              return const ProfileAuthFailScreen();
            } else {
              return ProfileAuthShell(
                illustration: Image.asset(
                  Resources.images.profile.profileUnlock,
                  fit: BoxFit.contain,
                ),
                contentWidthFactor: 0.5,
                content: state is ProfileUnlockInitial
                    ? ReactiveForm(
                        formGroup: context.watch<ProfileUnlockCubit>().form,
                        child: AutofillGroup(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                appLocalizationsOf(context)
                                    .welcomeBackUserEmphasized(state.username!)
                                    .toUpperCase(),
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.headline5,
                              ),
                              AbsorbPointer(
                                child: SizedBox(
                                  height: 32,
                                  child: Opacity(
                                      opacity: 0,
                                      child: TextFormField(
                                        controller: TextEditingController(
                                            text: state.username),
                                        autofillHints: const [
                                          AutofillHints.username
                                        ],
                                      )),
                                ),
                              ),
                              ReactiveTextField(
                                formControlName: 'password',
                                autofocus: true,
                                obscureText: true,
                                autofillHints: const [AutofillHints.password],
                                decoration: InputDecoration(
                                  labelText:
                                      appLocalizationsOf(context).password,
                                  prefixIcon: const Icon(Icons.lock),
                                ),
                                validationMessages: kValidationMessages(
                                    appLocalizationsOf(context)),
                                onSubmitted: (_) =>
                                    context.read<ProfileUnlockCubit>().submit(),
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () {
                                    context
                                        .read<ArDriveAnalytics>()
                                        .trackScreenEvent(
                                          screenName: "unlockScreen",
                                          eventName: "unlockButton",
                                        );
                                    context.read<ProfileUnlockCubit>().submit();
                                  },
                                  child: Text(appLocalizationsOf(context)
                                      .unlockEmphasized),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed: () {
                                  context
                                      .read<ArDriveAnalytics>()
                                      .trackScreenEvent(
                                        screenName: "unlockScreen",
                                        eventName: "forgetWalletButton",
                                      );
                                  context.read<ProfileCubit>().logoutProfile();
                                },
                                child: Text(
                                  appLocalizationsOf(context).forgetWallet,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox(),
              );
            }
          },
        ),
      );
}
