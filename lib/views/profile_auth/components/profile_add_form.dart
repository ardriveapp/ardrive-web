import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:file_picker_cross/file_picker_cross.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

class ProfileAddForm extends StatelessWidget {
  @override
  Widget build(BuildContext context) => BlocProvider<ProfileAddCubit>(
        create: (context) => ProfileAddCubit(
          profileCubit: context.bloc<ProfileCubit>(),
          profileDao: context.repository<ProfileDao>(),
          arweave: context.repository<ArweaveService>(),
        ),
        child: BlocBuilder<ProfileAddCubit, ProfileAddState>(
          builder: (context, state) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Add Profile',
                style: Theme.of(context).textTheme.bodyText1,
              ),
              Container(height: 16),
              if (state is ProfileAddPromptWallet)
                ElevatedButton(
                  child: Text('SELECT WALLET'),
                  onPressed: () => _pickWallet(context),
                )
              else if (state is ProfileAddPromptDetails)
                ReactiveForm(
                  formGroup: context.bloc<ProfileAddCubit>().form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        !state.isNewUser
                            ? 'Welcome! Please provide the same password as you have used before'
                            : 'Welcome new user!',
                      ),
                      Container(height: 16),
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
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          child: Text('ADD'),
                          onPressed: () =>
                              context.bloc<ProfileAddCubit>().submit(),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );

  void _pickWallet(BuildContext context) async {
    var chooseResult;
    try {
      chooseResult = await FilePickerCross.pick();
      // ignore: empty_catches
    } catch (err) {}

    if (chooseResult != null && chooseResult.type != null) {
      await context.bloc<ProfileAddCubit>().pickWallet(chooseResult.toString());
    }
  }
}
