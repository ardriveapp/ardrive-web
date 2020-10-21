import 'package:ardrive/blocs/blocs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

import 'profile_auth_shell.dart';

class ProfileAuthAddScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      BlocBuilder<ProfileAddCubit, ProfileAddState>(
        builder: (context, state) => state is ProfileAddPromptDetails
            ? ProfileAuthShell(
                illustration: Image.asset(
                  'assets/illustrations/illus_profile_add.png',
                  fit: BoxFit.fitWidth,
                ),
                content: FractionallySizedBox(
                  widthFactor: 0.5,
                  child: ReactiveForm(
                    formGroup: context.bloc<ProfileAddCubit>().form,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          state.isExistingUser
                              ? 'WELCOME BACK'
                              : 'LET\'S GET STARTED',
                          style: Theme.of(context).textTheme.headline5,
                        ),
                        Container(height: 32),
                        if (state.isExistingUser) ...{
                          Text(
                            'Please provide the same password as you have used before.',
                            textAlign: TextAlign.center,
                          ),
                          Container(height: 16),
                        },
                        ReactiveTextField(
                          formControlName: 'username',
                          autofocus: true,
                          decoration: InputDecoration(labelText: 'Username'),
                        ),
                        Container(height: 16),
                        ReactiveTextField(
                          formControlName: 'password',
                          obscureText: true,
                          decoration: InputDecoration(labelText: 'Password'),
                          validationMessages: {
                            'password-incorrect':
                                'You entered an incorrect password',
                          },
                        ),
                        Container(height: 32),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            child: Text('ADD PROFILE'),
                            onPressed: () =>
                                context.bloc<ProfileAddCubit>().submit(),
                          ),
                        ),
                        Container(height: 16),
                        TextButton(
                          child: Text('Change wallet'),
                          onPressed: () =>
                              context.bloc<ProfileAddCubit>().promptForWallet(),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : Container(),
      );
}
