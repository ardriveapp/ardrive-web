import 'package:drive/blocs/blocs.dart';
import 'package:drive/repositories/repositories.dart';
import 'package:drive/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'views/views.dart';

Database db;

void main() async {
  db = Database();
  runApp(App());
}

class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<DrivesDao>(
          create: (context) => DrivesDao(db),
        ),
        RepositoryProvider<DriveDao>(
          create: (context) => DriveDao(db),
        ),
      ],
      child: MaterialApp(
        title: 'Drive',
        theme: appTheme(),
        home: AppShell(title: 'Drive'),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  AppShell({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _AppShellState createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => DrivesBloc(
        drivesDao: context.repository<DrivesDao>(),
      ),
      child: Scaffold(
        body: Row(
          children: [
            AppDrawer(),
            Expanded(
              child: BlocBuilder<DrivesBloc, DrivesState>(
                builder: (context, state) => state is DrivesReady
                    ? BlocProvider(
                        key: ValueKey(state.selectedDriveId),
                        create: (context) => DriveDetailBloc(
                          driveId: state.selectedDriveId,
                          driveDao: context.repository<DriveDao>(),
                        ),
                        child: DriveDetailPage(),
                      )
                    : Container(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
