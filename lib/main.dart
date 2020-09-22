import 'package:arweave/arweave.dart';
import 'package:drive/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'app_shell.dart';
import 'blocs/blocs.dart';
import 'repositories/repositories.dart';
import 'services/services.dart';
import 'views/views.dart';

ArweaveService arweave;
Database db;

void main() async {
  arweave =
      ArweaveService(Arweave(gatewayUrl: Uri.parse('https://arweave.dev')));

  db = Database();

  runApp(App());
}

class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => UserBloc(),
      child: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<ArweaveService>(create: (_) => arweave),
          RepositoryProvider<DrivesDao>(create: (_) => db.drivesDao),
          RepositoryProvider<DriveDao>(create: (_) => db.driveDao),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (context) => UploadBloc(
                userBloc: context.bloc<UserBloc>(),
                arweave: context.repository<ArweaveService>(),
                driveDao: context.repository<DriveDao>(),
              ),
            ),
            BlocProvider(
              create: (context) => SyncBloc(
                userBloc: context.bloc<UserBloc>(),
                arweave: context.repository<ArweaveService>(),
                drivesDao: context.repository<DrivesDao>(),
              ),
            ),
            BlocProvider(
              create: (context) => DrivesBloc(
                syncBloc: context.bloc<SyncBloc>(),
                userBloc: context.bloc<UserBloc>(),
                arweave: context.repository<ArweaveService>(),
                drivesDao: context.repository<DrivesDao>(),
              ),
            ),
          ],
          child: MaterialApp(
            title: 'Drive',
            theme: appTheme(),
            home: BlocBuilder<DrivesBloc, DrivesState>(
              builder: (context, state) {
                final selectedDriveId =
                    state is DrivesLoadSuccess ? state.selectedDriveId : null;

                return BlocProvider(
                  key: ValueKey(selectedDriveId),
                  create: (context) => DriveDetailBloc(
                    driveId: selectedDriveId,
                    userBloc: context.bloc<UserBloc>(),
                    uploadBloc: context.bloc<UploadBloc>(),
                    arweave: context.repository<ArweaveService>(),
                    driveDao: context.repository<DriveDao>(),
                  ),
                  child: AppShell(
                    page: BlocBuilder<DrivesBloc, DrivesState>(
                      builder: (context, state) => state is DrivesLoadSuccess &&
                              state.selectedDriveId != null
                          ? DriveDetailView()
                          : Container(),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
