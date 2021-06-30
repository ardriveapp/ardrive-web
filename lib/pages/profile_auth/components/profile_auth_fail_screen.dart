import 'dart:html';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'profile_auth_shell.dart';

class ProfileAuthFailScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ProfileAuthShell(
        illustration: Image.asset(
          R.images.profile.profileWelcome,
          fit: BoxFit.contain,
        ),
        contentWidthFactor: 0.5,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Login Failed',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headline5,
            ),
            const SizedBox(height: 32),
            Text(
              'Sorry, login failed. Please try again.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headline6,
            ),
            const SizedBox(height: 32),
            TextButton(
              child: Text('Log In'),
              onPressed: () {
                context.read<ProfileCubit>().logoutProfile();
                window.location.reload();
                context.read<ProfileAddCubit>().promptForWallet();
              },
            ),
          ],
        ),
      );
}
