import 'package:drive/blocs/blocs.dart';
import 'package:drive/models/models.dart';
import 'package:file_picker_cross/file_picker_cross.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

class AddProfileForm extends StatelessWidget {
  @override
  Widget build(BuildContext context) => BlocProvider<AddProfileCubit>(
        create: (context) => AddProfileCubit(
          profileBloc: context.bloc<ProfileBloc>(),
          profileDao: context.repository<ProfileDao>(),
        ),
        child: BlocBuilder<AddProfileCubit, AddProfileState>(
          builder: (context, state) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Add Profile',
                style: Theme.of(context).textTheme.bodyText1,
              ),
              Container(height: 16),
              if (state == AddProfileState.promptWallet)
                ElevatedButton(
                  child: Text('SELECT WALLET'),
                  onPressed: () => _pickWallet(context),
                )
              else if (state == AddProfileState.promptDetails)
                ReactiveForm(
                  formGroup: context.bloc<AddProfileCubit>().form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          child: Text('ADD'),
                          onPressed: () =>
                              context.bloc<AddProfileCubit>().submit(),
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
      context.bloc<AddProfileCubit>().setWallet(chooseResult.toString());
    }
  }
}
