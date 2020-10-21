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
          profileBloc: context.bloc<ProfileBloc>(),
          profileDao: context.repository<ProfileDao>(),
          arweave: context.repository<ArweaveService>(),
        ),
        child: BlocBuilder<ProfileAddCubit, ProfileAddState>(
          builder: (context, state) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state is ProfileAddPromptWallet) ...{
                Text(
                  'WELCOME TO',
                  style: Theme.of(context).textTheme.headline5,
                ),
                Container(height: 32),
                Text(
                  'Your private and secure, decentralized, pay-as-you-go, censorship-resistant and permanent hard drive.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headline6,
                ),
                Container(height: 32),
                ElevatedButton(
                  child: Text('SELECT WALLET'),
                  onPressed: () => _pickWallet(context),
                ),
              } else if (state is ProfileAddPromptDetails)
                ReactiveForm(
                  formGroup: context.bloc<ProfileAddCubit>().form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'WELCOME BACK',
                        style: Theme.of(context).textTheme.headline5,
                      ),
                      Container(height: 32),
                      Text(
                        !state.isNewUser
                            ? 'Please provide the same password as you have used before.'
                            : 'Welcome new user!',
                        textAlign: TextAlign.center,
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
                      Container(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          child: Text('UNLOCK'),
                          onPressed: () =>
                              context.bloc<ProfileAddCubit>().submit(),
                        ),
                      ),
                      Container(height: 16),
                      TextButton(
                        child: Text('Change wallet'),
                        onPressed: () {},
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
