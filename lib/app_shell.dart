import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'blocs/blocs.dart';
import 'repositories/repositories.dart';
import 'views/views.dart';

class AppShell extends StatefulWidget {
  AppShell({Key key}) : super(key: key);

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
            VerticalDivider(width: 0),
            Expanded(
              child: BlocConsumer<DrivesBloc, DrivesState>(
                listener: (context, state) async {
                  if (state is DrivesReady && state.drives.isEmpty)
                    _promptToCreateNewDrive(context);
                },
                builder: (context, state) =>
                    state is DrivesReady && state.selectedDriveId != null
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

  void _promptToCreateNewDrive(BuildContext context) async {
    final driveName = await showTextFieldDialog(
      context,
      title: 'New drive',
      fieldLabel: 'Drive name',
      confirmingActionLabel: 'CREATE',
    );
    context.bloc<DrivesBloc>().add(NewDrive(driveName));
  }
}
