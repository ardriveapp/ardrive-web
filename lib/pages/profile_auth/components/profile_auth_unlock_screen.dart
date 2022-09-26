import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/profile_auth/components/profile_auth_add_screen.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/authentication/biometric_authentication.dart';
import 'package:ardrive/services/authentication/biometric_permission_dialog.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/secure_key_value_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
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
          biometricAuthentication: BiometricAuthentication(
            LocalAuthentication(),
            SecureKeyValueStore(
              const FlutterSecureStorage(),
            ),
          ),
        ),
        child: BlocListener<ProfileUnlockCubit, ProfileUnlockState>(
          listener: (context, state) {
            if (state is ProfileUnlockWithBiometrics) {
              context
                  .read<ProfileUnlockCubit>()
                  .unlockWithStoredPassword(context);
            } else if (state is ProfileUnlockBiometricFailure) {
              showBiometricExceptionDialogForException(
                context,
                state.exception,
                () => context.read<ProfileUnlockCubit>().usePasswordLogin(),
              );
            }
          },
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
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      state is ProfileUnlockInitial
                          ? ReactiveForm(
                              formGroup:
                                  context.watch<ProfileUnlockCubit>().form,
                              child: AutofillGroup(
                                child: Column(
                                  children: [
                                    Text(
                                      appLocalizationsOf(context)
                                          .welcomeBackUserEmphasized(
                                              state.username!)
                                          .toUpperCase(),
                                      textAlign: TextAlign.center,
                                      style:
                                          Theme.of(context).textTheme.headline5,
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
                                        key: ValueKey(state.autoFocus),
                                        formControlName: 'password',
                                        autofocus: state.autoFocus,
                                        obscureText: true,
                                        autofillHints: const [
                                          AutofillHints.password
                                        ],
                                        decoration: InputDecoration(
                                          labelText: appLocalizationsOf(context)
                                              .password,
                                          prefixIcon: const Icon(Icons.lock),
                                        ),
                                        validationMessages: kValidationMessages(
                                            appLocalizationsOf(context)),
                                        onSubmitted: (_) async {
                                          context
                                              .read<ProfileUnlockCubit>()
                                              .submit();
                                        }),
                                  ],
                                ),
                              ),
                            )
                          : const SizedBox(),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () =>
                            context.read<ProfileCubit>().logoutProfile(),
                        child: Text(
                          appLocalizationsOf(context).forgetWallet,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: BiometricToggle(
                          onDisableBiometric: () {
                            context
                                .read<ProfileUnlockCubit>()
                                .usePasswordLogin();
                          },
                        ),
                      )
                    ]));
              }
            },
          ),
        ),
      );
}
