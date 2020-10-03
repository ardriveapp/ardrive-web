import 'package:drive/blocs/blocs.dart';
import 'package:drive/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class UnlockProfileForm extends StatefulWidget {
  @override
  _UnlockProfileFormState createState() => _UnlockProfileFormState();
}

class _UnlockProfileFormState extends State<UnlockProfileForm> {
  TextEditingController passwordController;

  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    passwordController = TextEditingController();
  }

  @override
  Widget build(BuildContext context) => BlocProvider<UnlockProfileBloc>(
        create: (context) => UnlockProfileBloc(
          profileBloc: context.bloc<ProfileBloc>(),
          profileDao: context.repository<ProfileDao>(),
        ),
        child: BlocBuilder<UnlockProfileBloc, UnlockProfileState>(
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
    if (_formKey.currentState.validate()) {
      context.bloc<ProfileBloc>().add(ProfileLoad(passwordController.text));
    }
  }
}
