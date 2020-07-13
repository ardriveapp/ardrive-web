import 'package:drive/blocs/blocs.dart';
import 'package:drive/repositories/repositories.dart';
import 'package:drive/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'app_shell.dart';
import 'blocs/blocs.dart';
import 'repositories/repositories.dart';
import 'views/views.dart';

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
            if (state is UserUnauthenticated) return UnauthedPage();
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
                child: MultiBlocProvider(
                  providers: [
                    BlocProvider(
                      create: (context) => DrivesBloc(
                        drivesDao: context.repository<DrivesDao>(),
                      ),
                    ),
                    BlocProvider(
                      create: (context) => UploadBloc(
                        driveDao: context.repository<DriveDao>(),
                      ),
                    ),
                  ],
                  child: AppShell(
                    page: BlocConsumer<DrivesBloc, DrivesState>(
                      listener: (context, state) async {
                        if (state is DrivesReady && state.drives.isEmpty)
                          promptToCreateNewDrive(context);
                      },
                      builder: (context, state) =>
                          state is DrivesReady && state.selectedDriveId != null
                              ? DriveDetailPage()
                              : UploadsPage(),
                    ),
                  ),
                ),
              );

            return Container();
          },
        ),
      ),
    );
  }
}
