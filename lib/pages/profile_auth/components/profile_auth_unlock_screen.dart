import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/profile_auth/components/profile_auth_add_screen.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/authentication/biometric_authentication.dart';
import 'package:ardrive/services/authentication/biometric_permission_dialog.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

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
          biometricAuthentication: context.read<BiometricAuthentication>(),
        ),
        child: BlocListener<ProfileUnlockCubit, ProfileUnlockState>(
          listener: (context, state) {
            if (state is ProfileUnlockWithBiometrics) {
              context
                  .read<ProfileUnlockCubit>()
                  .unlockWithStoredPassword(context);
            } else if (state is ProfileUnlockBiometricFailure) {
              if (state.exception is BiometricUnknownException) {
                context.read<ProfileUnlockCubit>().usePasswordLogin();
                return;
              }
              showBiometricExceptionDialogForException(
                context,
                state.exception,
                () => context.read<ProfileUnlockCubit>().usePasswordLogin(),
              );
            }
          },
          child: BlocBuilder<ProfileUnlockCubit, ProfileUnlockState>(
            buildWhen: (previous, current) =>
                current is! ProfileUnlockWithBiometrics,
            builder: (context, state) {
              if (state is ProfileUnlockFailure) {
                return const ProfileAuthFailScreen();
              } else {
                return ProfileAuthShell(
                    useLogo: false,
                    resizeToAvoidBottomInset: false,
                    illustration: Image.asset(
                      Resources.images.profile.profileUnlock,
                      fit: BoxFit.contain,
                    ),
                    contentWidthFactor: 0.5,
                    content: Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.max,
                                children: [
                                  Image.asset(
                                    ArDriveTheme.of(context).themeData.name ==
                                            'light'
                                        ? Resources.images.brand
                                            .logoHorizontalNoSubtitleLight
                                        : Resources.images.brand
                                            .logoHorizontalNoSubtitleDark,
                                    height: 126,
                                    fit: BoxFit.contain,
                                  ),
                                  const SizedBox(height: 32),
                                  state is ProfileUnlockInitial
                                      ? ReactiveForm(
                                          formGroup: context
                                              .watch<ProfileUnlockCubit>()
                                              .form,
                                          child: AutofillGroup(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.max,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  appLocalizationsOf(context)
                                                      .welcomeBackUserEmphasized(
                                                          state.username!)
                                                      .toUpperCase(),
                                                  textAlign: TextAlign.center,
                                                  style: ArDriveTypography
                                                      .headline
                                                      .headline4Bold(),
                                                ),
                                                AbsorbPointer(
                                                  child: SizedBox(
                                                    height: 32,
                                                    child: Opacity(
                                                        opacity: 0,
                                                        child: TextFormField(
                                                          controller:
                                                              TextEditingController(
                                                                  text: state
                                                                      .username),
                                                          autofillHints: const [
                                                            AutofillHints
                                                                .username
                                                          ],
                                                        )),
                                                  ),
                                                ),
                                                ArDriveTextField(
                                                    key: ValueKey(
                                                        state.autoFocus),
                                                    autofocus: state.autoFocus,
                                                    obscureText: true,
                                                    autofillHints: const [
                                                      AutofillHints.password
                                                    ],
                                                    hintText: 'Password',
                                                    errorMessage:
                                                        appLocalizationsOf(
                                                                context)
                                                            .validationRequired,
                                                    onFieldSubmitted:
                                                        (_) async {
                                                      context
                                                          .read<
                                                              ProfileUnlockCubit>()
                                                          .submit();
                                                    }),
                                                const SizedBox(height: 16),
                                                SizedBox(
                                                  width: double.infinity,
                                                  child: ArDriveButton(
                                                    onPressed: () => context
                                                        .read<
                                                            ProfileUnlockCubit>()
                                                        .submit(),
                                                    text: appLocalizationsOf(
                                                            context)
                                                        .unlockEmphasized,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                      : const SizedBox(),
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 16,
                                      right: 16,
                                      top: 16,
                                    ),
                                    child: BiometricToggle(
                                      onEnableBiometric: () {
                                        /// Biometrics was enabled
                                        context
                                            .read<ProfileUnlockCubit>()
                                            .unlockWithStoredPassword(
                                              context,
                                              needBiometrics: false,
                                            );
                                      },
                                      onDisableBiometric: () {
                                        context
                                            .read<ProfileUnlockCubit>()
                                            .usePasswordLogin();
                                      },
                                    ),
                                  ),
                                ]),
                          ),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: ArDriveButton(
                              onPressed: () {
                                final actions = [
                                  ModalAction(
                                    action: () {
                                      Navigator.pop(context);
                                    },
                                    title: appLocalizationsOf(context).cancel,
                                  ),
                                  ModalAction(
                                    action: () {
                                      Navigator.pop(context);

                                      context
                                          .read<ProfileCubit>()
                                          .logoutProfile();
                                    },
                                    title: appLocalizationsOf(context).ok,
                                  )
                                ];
                                showStandardDialog(
                                  context,
                                  title: appLocalizationsOf(context)
                                      .forgetWalletTitle,
                                  content: appLocalizationsOf(context)
                                      .forgetWalletDescription,
                                  actions: actions,
                                );
                              },
                              style: ArDriveButtonStyle.tertiary,
                              text: appLocalizationsOf(context).forgetWallet,
                            ),
                          ),
                        ],
                      ),
                    ));
              }
            },
          ),
        ),
      );
}
