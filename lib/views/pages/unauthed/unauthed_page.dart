import 'dart:convert';

import 'package:file_picker_cross/file_picker_cross.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../blocs/blocs.dart';

class UnauthedPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RaisedButton(
                    onPressed: () => _promptToLogin(context),
                    child: Text('Login'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _promptToLogin(BuildContext context) async {
    final chooseResult = await FilePickerCross.pick();
    if (chooseResult.type != null) {
      final jwk = json.decode(chooseResult.toString());
      context.bloc<UserBloc>().add(AttemptLogin(jwk));
    }
  }
}
