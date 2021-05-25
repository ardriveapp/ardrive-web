import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
                            ? 'WELCOME BACK'
                            : 'LET\'S GET STARTED',
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
                        decoration: InputDecoration(
                          labelText: 'Username',
                          prefixIcon: const Icon(Icons.person),
                        ),
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
                          ReactiveCheckbox(formControlName: 'agreementConsent'),
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
                          child: Text('ADD PROFILE'),
                          onPressed: () =>
                              context.read<ProfileAddCubit>().submit(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        child: context
                                .read<ProfileAddCubit>()
                                .isArconnectInstalled()
                            ? Text('LOG OUT')
                            : Text('Change wallet'),
                        onPressed: () =>
                            context.read<ProfileAddCubit>().promptForWallet(),
                      ),
                    ],
                  ),
                ),
              )
            : const SizedBox(),
      );
}
