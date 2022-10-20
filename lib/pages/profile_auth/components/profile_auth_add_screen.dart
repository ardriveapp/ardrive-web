import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/services/authentication/biometric_authentication.dart';
import 'package:ardrive/services/authentication/biometric_permission_dialog.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/split_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

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
                                  onTap: () => openUrl(
                                    url: 'https://ardrive.io/tos-and-privacy/',
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
    this.onError,
  });

  final Function()? onEnableBiometric;
  final Function()? onDisableBiometric;
  final Function()? onError;

  @override
  State<BiometricToggle> createState() => _BiometricToggleState();
}

class _BiometricToggleState extends State<BiometricToggle> {
  @override
  void initState() {
    super.initState();
    _isBiometricsEnabled();
    _listenToBiometricChange();
  }

  bool _isEnabled = false;
  String get biometricText => _isEnabled
      ? appLocalizationsOf(context).biometricLoginEnabled
      : appLocalizationsOf(context).biometricLoginDisabled;

  Future<bool> _checkBiometricsSupport() async {
    final auth = context.read<BiometricAuthentication>();

    return auth.checkDeviceSupport();
  }

  Future<void> _isBiometricsEnabled() async {
    _isEnabled = await context.read<BiometricAuthentication>().isEnabled();

    setState(() {});
  }

  void _listenToBiometricChange() {
    context.read<BiometricAuthentication>().enabledStream.listen((event) {
      if (event != _isEnabled && mounted) {
        setState(() {
          _isEnabled = event;
        });
      }
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            key: ValueKey(_isEnabled),
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
                final auth = context.read<BiometricAuthentication>();

                try {
                  if (await auth.authenticate(context)) {
                    setState(() {
                      _isEnabled = true;
                    });
                    context.read<BiometricAuthentication>().enable();
                    widget.onEnableBiometric?.call();
                    return;
                  }
                } catch (e) {
                  widget.onError?.call();
                  if (e is BiometricException) {
                    showBiometricExceptionDialogForException(
                      context,
                      e,
                      () => widget.onDisableBiometric?.call(),
                    );
                  }
                }
              } else {
                context.read<BiometricAuthentication>().disable();

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
