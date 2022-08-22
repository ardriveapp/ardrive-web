import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/split_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
                          autofocus: true,
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
                      ],
                    ),
                  ),
                ),
              )
            : const SizedBox(),
      );
}
