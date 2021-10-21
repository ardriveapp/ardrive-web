import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:url_launcher/link.dart';

import 'profile_auth_shell.dart';

class ProfileAuthAddScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      BlocBuilder<ProfileAddCubit, ProfileAddState>(
        builder: (context, state) => state is ProfileAddPromptDetails
            ? ProfileAuthShell(
                illustration: Image.asset(
                  R.images.profile.profileAdd,
                  fit: BoxFit.contain,
                ),
                contentWidthFactor: 0.5,
                content: ReactiveForm(
                  formGroup: context.watch<ProfileAddCubit>().form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        state.isExistingUser
                            ? AppLocalizations.of(context)!
                                .welcomeBack
                                .toUpperCase()
                            : AppLocalizations.of(context)!
                                .letsGetStarted
                                .toUpperCase(),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headline5,
                      ),
                      const SizedBox(height: 32),
                      if (state.isExistingUser)
                        Text(
                            'Please provide the same password as the one you used before.',
                            textAlign: TextAlign.center)
                      else
                        Text(
                            'Your password can never be changed or recovered. Please keep it safe!',
                            textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ReactiveTextField(
                        formControlName: 'username',
                        autofocus: true,
                        autofillHints: [AutofillHints.username],
                        decoration: InputDecoration(
                          labelText: 'Username',
                          prefixIcon: const Icon(Icons.person),
                        ),
                        onSubmitted: () =>
                            context.read<ProfileAddCubit>().submit(),
                        validationMessages: (_) => kValidationMessages,
                      ),
                      const SizedBox(height: 16),
                      ReactiveTextField(
                        formControlName: 'password',
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock),
                        ),
                        autofillHints: [AutofillHints.password],
                        onSubmitted: () =>
                            context.read<ProfileAddCubit>().submit(),
                        validationMessages: (_) => kValidationMessages,
                      ),
                      if (!state.isExistingUser) ...{
                        const SizedBox(height: 16),
                        ReactiveTextField(
                          formControlName: 'passwordConfirmation',
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Confirm Password',
                            prefixIcon: const Icon(Icons.lock),
                          ),
                          onSubmitted: () =>
                              context.read<ProfileAddCubit>().submit(),
                          validationMessages: (_) => const {
                            ...kValidationMessages,
                            'mustMatch':
                                'The confirmation password does not match.',
                          },
                        ),
                      },
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ReactiveCheckbox(
                            formControlName: 'agreementConsent',
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Link(
                              uri: Uri.parse(
                                  'https://ardrive.io/tos-and-privacy/'),
                              target: LinkTarget.blank,
                              builder: (context, onPressed) => GestureDetector(
                                onTap: onPressed,
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(text: 'I agree to the '),
                                      TextSpan(
                                        text:
                                            'ArDrive terms of service and privacy policy',
                                        style: TextStyle(
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                      TextSpan(text: '.'),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () =>
                              context.read<ProfileAddCubit>().submit(),
                          child: Text('ADD PROFILE'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () =>
                            context.read<ProfileAddCubit>().promptForWallet(),
                        child: context
                                .read<ProfileAddCubit>()
                                .isArconnectInstalled()
                            ? Text('LOG OUT')
                            : Text('Change wallet'),
                      ),
                    ],
                  ),
                ),
              )
            : const SizedBox(),
      );
}
