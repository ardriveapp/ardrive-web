import 'dart:convert';
import 'dart:io';

import 'package:drive/blocs/blocs.dart';
import 'package:drive/repositories/repositories.dart';
import 'package:drive/theme/theme.dart';
import 'package:file_chooser/file_chooser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'app_shell.dart';

Database db;

void main() async {
  db = Database();
  runApp(App());
}

class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => UserBloc(),
      child: MaterialApp(
        title: 'Drive',
        theme: appTheme(),
        home: BlocBuilder<UserBloc, UserState>(
          builder: (context, state) {
            if (state is UserUnauthenticated)
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
            if (state is UserAuthenticated)
              return MultiRepositoryProvider(
                providers: [
                  RepositoryProvider<DrivesDao>(
                    create: (context) => db.drivesDao,
                  ),
                  RepositoryProvider<DriveDao>(
                    create: (context) => db.driveDao,
                  ),
                ],
                child: AppShell(),
              );

            return Container();
          },
        ),
      ),
    );
  }

  void _promptToLogin(BuildContext context) async {
    final chooseResult = await showOpenPanel();
    if (!chooseResult.canceled) {
      final jwk = json.decode(
        await new File(chooseResult.paths[0]).readAsString(),
      );

      context.bloc<UserBloc>().add(AttemptLogin(jwk));
    }
  }
}
