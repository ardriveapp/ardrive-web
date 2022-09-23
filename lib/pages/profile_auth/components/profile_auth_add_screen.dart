import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/services/authentication/biometric_authentication.dart';
import 'package:ardrive/services/authentication/biometric_permission_dialog.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:ardrive/utils/secure_key_value_store.dart';
import 'package:ardrive/utils/split_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:url_launcher/url_launcher.dart';

import 'profile_auth_shell.dart';

class ProfileAuthAddScreen extends StatelessWidget {
  const ProfileAuthAddScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<ProfileAddCubit, ProfileAddState>(
        builder: (context, state) => state is ProfileAddPromptDetails
            ? ProfileAuthShell(
                illustration: Image.asset(
                  Resources.images.profile.profileAdd,
                  fit: BoxFit.contain,
                ),
                contentWidthFactor: 0.5,
                content: AutofillGroup(
                  child: ReactiveForm(
                    formGroup: context.watch<ProfileAddCubit>().form,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          state.isExistingUser
                              ? appLocalizationsOf(context)
                                  .welcomeBackEmphasized
                              : appLocalizationsOf(context)
                                  .letsGetStartedEmphasized,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headline5,
                        ),
                        const SizedBox(height: 32),
                        if (state.isExistingUser)
                          Text(
                              appLocalizationsOf(context)
                                  .pleaseProvideSamePassword,
                              textAlign: TextAlign.center)
                        else
                          Text(
                              appLocalizationsOf(context)
                                  .passwordCanNeverBeChanged,
                              textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ReactiveTextField(
                          formControlName: 'username',
                          autofocus: false,
                          autofillHints: const [AutofillHints.username],
                          decoration: InputDecoration(
                            labelText: appLocalizationsOf(context).username,
                            prefixIcon: const Icon(Icons.person),
                          ),
                          onSubmitted: (_) =>
                              context.read<ProfileAddCubit>().submit(),
                          validationMessages:
                              kValidationMessages(appLocalizationsOf(context)),
                        ),
                        const SizedBox(height: 16),
                        ReactiveTextField(
                          formControlName: 'password',
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: appLocalizationsOf(context).password,
                            prefixIcon: const Icon(Icons.lock),
                          ),
                          autofillHints: const [AutofillHints.password],
                          onSubmitted: (_) =>
                              context.read<ProfileAddCubit>().submit(),
                          validationMessages:
                              kValidationMessages(appLocalizationsOf(context)),
                        ),
                        if (!state.isExistingUser) ...[
                          const SizedBox(height: 16),
                          ReactiveTextField(
                            formControlName: 'passwordConfirmation',
                            obscureText: true,
                            decoration: InputDecoration(
                              labelText:
                                  appLocalizationsOf(context).confirmPassword,
                              prefixIcon: const Icon(Icons.lock),
                            ),
                            onSubmitted: (_) =>
                                context.read<ProfileAddCubit>().submit(),
                            validationMessages: {
                              ...kValidationMessages(
                                  appLocalizationsOf(context)),
                              'mustMatch': (_) =>
                                  appLocalizationsOf(context).passwordMismatch,
                            },
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ReactiveCheckbox(
                                formControlName: 'agreementConsent',
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: GestureDetector(
                                  onTap: () => launchUrl(
                                    Uri.parse(
                                      'https://ardrive.io/tos-and-privacy/',
                                    ),
                                  ),
                                  child: Text.rich(
                                    TextSpan(
                                      children:
                                          splitTranslationsWithMultipleStyles<
                                              InlineSpan>(
                                        originalText:
                                            appLocalizationsOf(context)
                                                .aggreeToTerms_body,
                                        defaultMapper: (text) =>
                                            TextSpan(text: text),
                                        parts: {
                                          appLocalizationsOf(context)
                                                  .aggreeToTerms_link:
                                              (text) => TextSpan(
                                                    text: text,
                                                    style: const TextStyle(
                                                      decoration: TextDecoration
                                                          .underline,
                                                    ),
                                                  ),
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () =>
                                context.read<ProfileAddCubit>().submit(),
                            child: Text(appLocalizationsOf(context)
                                .addProfileEmphasized),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () =>
                              context.read<ProfileAddCubit>().promptForWallet(),
                          child: context
                                  .read<ProfileAddCubit>()
                                  .isArconnectInstalled()
                              ? Text(
                                  appLocalizationsOf(context).logOutEmphasized)
                              : Text(appLocalizationsOf(context).changeWallet),
                        ),
                        const Align(
                          alignment: Alignment.center,
                          child: BiometricToggle(),
                        )
                      ],
                    ),
                  ),
                ),
              )
            : const SizedBox(),
      );
}

// TODO(@thiagocarvalhodev): Move to a new file
class BiometricToggle extends StatefulWidget {
  const BiometricToggle({
    super.key,
    this.onDisableBiometric,
    this.onEnableBiometric,
  });

  final Function()? onEnableBiometric;
  final Function()? onDisableBiometric;

  @override
  State<BiometricToggle> createState() => _BiometricToggleState();
}

class _BiometricToggleState extends State<BiometricToggle> {
  @override
  void initState() {
    super.initState();
    _isBiometricsEnabled();
  }

  final auth = BiometricAuthentication(
    LocalAuthentication(),
    SecureKeyValueStore(
      const FlutterSecureStorage(),
    ),
  );

  bool _isEnabled = false;
  String get biometricText => _isEnabled
      ? appLocalizationsOf(context).biometricLoginEnabled
      : appLocalizationsOf(context).biometricLoginDisabled;

  Future<bool> _checkBiometricsSupport() async {
    return auth.checkDeviceSupport();
  }

  Future<void> _isBiometricsEnabled() async {
    final store = await LocalKeyValueStore.getInstance();
    setState(() {
      _isEnabled = store.getBool('biometricEnabled') ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
        future: _checkBiometricsSupport(),
        builder: (context, snapshot) {
          final hasSupport = snapshot.data;
          if (hasSupport == null || !hasSupport) {
            return const SizedBox();
          }
          return SwitchListTile(
            title: Text(biometricText),
            value: _isEnabled,
            activeColor: Colors.white,
            activeTrackColor: Colors.black,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (value) async {
              setState(() {
                _isEnabled = value;
              });

              if (_isEnabled) {
                try {
                  if (await auth.authenticate(context)) {
                    final store = await LocalKeyValueStore.getInstance();

                    store.putBool('biometricEnabled', true);
                    widget.onEnableBiometric?.call();
                    setState(() {
                      _isEnabled = true;
                    });
                    return;
                  }
                } catch (e) {
                  showBiometricPermissionDialog(context);
                }
              } else {
                final store = await LocalKeyValueStore.getInstance();

                store.putBool('biometricEnabled', false);
                widget.onDisableBiometric?.call();
              }
              setState(() {
                _isEnabled = false;
              });
            },
          );
        });
  }
}
