import 'package:drive/blocs/blocs.dart';
import 'package:drive/models/models.dart';
import 'package:file_picker_cross/file_picker_cross.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

class AddProfileForm extends StatefulWidget {
  @override
  _AddProfileFormState createState() => _AddProfileFormState();
}

class _AddProfileFormState extends State<AddProfileForm> {
  final form = FormGroup({
    'username': FormControl(validators: [Validators.required]),
    'password': FormControl(
      validators: [Validators.required],
    ),
  });

  @override
  Widget build(BuildContext context) => BlocProvider<AddProfileBloc>(
        create: (context) => AddProfileBloc(
          profileBloc: context.bloc<ProfileBloc>(),
          profileDao: context.repository<ProfileDao>(),
        ),
        child: BlocBuilder<AddProfileBloc, AddProfileState>(
          builder: (context, state) => ReactiveForm(
            formGroup: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Add Profile',
                  style: Theme.of(context).textTheme.bodyText1,
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
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    child: Text('ADD'),
                    onPressed: () => _attemptToAddProfile(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  void _attemptToAddProfile(BuildContext context) async {
    if (form.valid) {
      var chooseResult;
      try {
        chooseResult = await FilePickerCross.pick();
        // ignore: empty_catches
      } catch (err) {}

      if (chooseResult != null && chooseResult.type != null) {
        context.bloc<AddProfileBloc>().add(
              AddProfileAttempted(
                username: form.control('username').value,
                password: form.control('password').value,
                walletJson: chooseResult.toString(),
              ),
            );
      }
    }
  }
}
