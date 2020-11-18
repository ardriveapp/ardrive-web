import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

import 'profile_auth_shell.dart';

class ProfileAuthUnlockScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) => BlocProvider<ProfileUnlockCubit>(
        create: (context) => ProfileUnlockCubit(
          profileCubit: context.read<ProfileCubit>(),
          profileDao: context.read<ProfileDao>(),
        ),
        child: BlocBuilder<ProfileUnlockCubit, ProfileUnlockState>(
          builder: (context, state) => ProfileAuthShell(
            illustration: Image.asset(
              R.images.profile.profileUnlock,
              fit: BoxFit.scaleDown,
            ),
            content: FractionallySizedBox(
              widthFactor: 0.5,
              child: state is ProfileUnlockInitial
                  ? ReactiveForm(
                      formGroup: context.watch<ProfileUnlockCubit>().form,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'WELCOME BACK, ${state.username.toUpperCase()}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headline5,
                          ),
                          Container(height: 32),
                          ReactiveTextField(
                            formControlName: 'password',
                            autofocus: true,
                            obscureText: true,
                            decoration: InputDecoration(labelText: 'Password'),
                            showErrors: (control) =>
                                control.dirty && control.invalid,
                            validationMessages: kValidationMessages,
                          ),
                          Container(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              child: Text('UNLOCK'),
                              onPressed: () =>
                                  context.read<ProfileUnlockCubit>().submit(),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Container(),
            ),
          ),
        ),
      );
}
