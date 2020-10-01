import 'package:drive/blocs/blocs.dart';
import 'package:drive/components/components.dart';
import 'package:drive/models/models.dart';
import 'package:file_picker_cross/file_picker_cross.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class UnlockProfileForm extends StatefulWidget {
  @override
  _UnlockProfileFormState createState() => _UnlockProfileFormState();
}

class _UnlockProfileFormState extends State<UnlockProfileForm> {
  TextEditingController usernameController;
  TextEditingController passwordController;

  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    usernameController = TextEditingController();
    passwordController = TextEditingController();
  }

  @override
  Widget build(BuildContext context) => BlocProvider<UnlockProfileBloc>(
        create: (context) => UnlockProfileBloc(
          profileBloc: context.bloc<ProfileBloc>(),
          profileDao: context.repository<ProfileDao>(),
        ),
        child: BlocConsumer<UnlockProfileBloc, UnlockProfileState>(
          listener: (context, state) {
            if (state is AddProfileInProgress) {
              showProgressDialog(context, 'Adding profile...');
            } else if (state is AddProfileSuccessful) {
              Navigator.pop(context);
              Navigator.pop(context);
            }
          },
          builder: (context, state) => Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Unlock Profile',
                  style: Theme.of(context).textTheme.bodyText1,
                ),
                Container(height: 16),
                TextFormField(
                  controller: passwordController,
                  validator: (value) =>
                      value.isEmpty ? 'This field is required' : null,
                  obscureText: true,
                  decoration: InputDecoration(labelText: 'Password'),
                ),
                SizedBox(
                  width: double.infinity,
                  child: RaisedButton(
                    child: Text('UNLOCK'),
                    onPressed: () => _attemptToAddProfile(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  void _attemptToAddProfile(BuildContext context) async {
    if (_formKey.currentState.validate()) {
      var chooseResult;
      try {
        chooseResult = await FilePickerCross.pick();
        // ignore: empty_catches
      } catch (err) {}

      if (chooseResult != null && chooseResult.type != null) {
        context.bloc<AddProfileBloc>().add(
              AddProfileAttempted(
                username: usernameController.text,
                password: passwordController.text,
                walletJson: chooseResult.toString(),
              ),
            );
      }
    }
  }
}
