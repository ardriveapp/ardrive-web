import 'package:drive/blocs/blocs.dart';
import 'package:drive/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

class UnlockProfileForm extends StatefulWidget {
  @override
  _UnlockProfileFormState createState() => _UnlockProfileFormState();
}

class _UnlockProfileFormState extends State<UnlockProfileForm> {
  final form = FormGroup({
    'password': FormControl(
      validators: [Validators.required],
    ),
  });

  @override
  Widget build(BuildContext context) => BlocProvider<UnlockProfileBloc>(
        create: (context) => UnlockProfileBloc(
          profileBloc: context.bloc<ProfileBloc>(),
          profileDao: context.repository<ProfileDao>(),
        ),
        child: BlocBuilder<UnlockProfileBloc, UnlockProfileState>(
          builder: (context, state) => ReactiveForm(
            formGroup: form,
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
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    child: Text('UNLOCK'),
                    onPressed: () => _attemptToUnlockProfile(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  void _attemptToUnlockProfile(BuildContext context) async {
    if (form.valid) {
      final password = form.control('password').value;
      context.bloc<ProfileBloc>().add(ProfileLoad(password));
    }
  }
}
