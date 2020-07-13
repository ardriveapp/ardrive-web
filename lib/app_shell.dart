import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'blocs/blocs.dart';
import 'repositories/repositories.dart';
import 'views/views.dart';

class AppShell extends StatefulWidget {
  final Widget page;

  AppShell({Key key, this.page}) : super(key: key);

  @override
  _AppShellState createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DrivesBloc, DrivesState>(
      builder: (context, state) {
        final content = Scaffold(
          body: Row(
            children: [
              AppDrawer(),
              VerticalDivider(width: 0),
              Expanded(
                child: widget.page,
              ),
            ],
          ),
        );

        if (state is DrivesReady && state.selectedDriveId != null)
          return BlocProvider(
            key: ValueKey(state.selectedDriveId),
            create: (context) => DriveDetailBloc(
              driveId: state.selectedDriveId,
              uploadBloc: context.bloc<UploadBloc>(),
              driveDao: context.repository<DriveDao>(),
            ),
            child: content,
          );

        return content;
      },
    );
  }
}
