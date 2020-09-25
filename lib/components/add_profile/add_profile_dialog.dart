import 'package:drive/blocs/blocs.dart';
import 'package:drive/models/models.dart';
import 'package:file_picker_cross/file_picker_cross.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../progress_dialog.dart';
import 'bloc/add_profile_bloc.dart';

class AddProfileForm extends StatefulWidget {
  @override
  _AddProfileFormState createState() => _AddProfileFormState();
}

class _AddProfileFormState extends State<AddProfileForm> {
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
  Widget build(BuildContext context) => BlocProvider<AddProfileBloc>(
        create: (context) => AddProfileBloc(
          profileBloc: context.bloc<ProfileBloc>(),
          profileDao: context.repository<ProfileDao>(),
        ),
        child: BlocConsumer<AddProfileBloc, AddProfileState>(
          listener: (context, state) {
            if (state is AddProfileInProgress) {
              showProgressDialog(context, 'Adding profile...');
            } else if (state is AddProfileSuccessful) {
              Navigator.pop(context);
              Navigator.pop(context);
            }
          },
          builder: (context, state) => AlertDialog(
            title: Text('Add profile'),
            content: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    autofocus: true,
                    controller: usernameController,
                    validator: (value) =>
                        value.isEmpty ? 'This field is required' : null,
                    decoration: InputDecoration(labelText: 'Username'),
                  ),
                  Container(height: 16),
                  TextFormField(
                    controller: passwordController,
                    validator: (value) =>
                        value.isEmpty ? 'This field is required' : null,
                    obscureText: true,
                    decoration: InputDecoration(labelText: 'Password'),
                  ),
                ],
              ),
            ),
            actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0),
            actions: [
              FlatButton(
                child: Text('CANCEL'),
                onPressed: () => Navigator.of(context).pop(null),
              ),
              FlatButton(
                child: Text('ADD'),
                onPressed: () => _attemptToAddProfile(context),
              ),
            ],
          ),
        ),
      );

  void _attemptToAddProfile(BuildContext context) async {
    {
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
}
