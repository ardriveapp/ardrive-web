import 'package:drive/blocs/blocs.dart';
import 'package:drive/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

class UnlockProfileForm extends StatelessWidget {
  @override
  Widget build(BuildContext context) => BlocProvider<UnlockProfileCubit>(
        create: (context) => UnlockProfileCubit(
          profileBloc: context.bloc<ProfileBloc>(),
          profileDao: context.repository<ProfileDao>(),
        ),
        child: BlocBuilder<UnlockProfileCubit, UnlockProfileState>(
          builder: (context, state) => ReactiveForm(
            formGroup: context.bloc<UnlockProfileCubit>().form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Unlock Profile',
                  style: Theme.of(context).textTheme.bodyText1,
                ),
                Container(height: 16),
                ReactiveTextField(
                  formControlName: 'password',
                  obscureText: true,
                  decoration: InputDecoration(labelText: 'Password'),
                  showErrors: (control) => control.dirty && control.invalid,
                  validationMessages: {
                    'password-incorrect': 'You entered an incorrect password',
                  },
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    child: Text('UNLOCK'),
                    onPressed: () =>
                        context.bloc<UnlockProfileCubit>().submit(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
