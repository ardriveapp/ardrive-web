import 'package:arweave/arweave.dart';
import 'package:drive/components/components.dart';
import 'package:drive/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'app_shell.dart';
import 'blocs/blocs.dart';
import 'models/models.dart';
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
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<ProfileDao>(create: (_) => db.profileDao),
        RepositoryProvider<ArweaveService>(create: (_) => arweave),
        RepositoryProvider<DrivesDao>(create: (_) => db.drivesDao),
        RepositoryProvider<DriveDao>(create: (_) => db.driveDao),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (context) => ProfileBloc(
              profileDao: context.repository<ProfileDao>(),
            ),
          ),
          BlocProvider(
            create: (context) => UploadBloc(
              profileBloc: context.bloc<ProfileBloc>(),
              arweave: context.repository<ArweaveService>(),
              driveDao: context.repository<DriveDao>(),
            ),
          ),
          BlocProvider(
            create: (context) => SyncBloc(
              profileBloc: context.bloc<ProfileBloc>(),
              arweave: context.repository<ArweaveService>(),
              drivesDao: context.repository<DrivesDao>(),
              driveDao: context.repository<DriveDao>(),
            ),
          ),
          BlocProvider(
            create: (context) => DrivesBloc(
              syncBloc: context.bloc<SyncBloc>(),
              profileBloc: context.bloc<ProfileBloc>(),
              arweave: context.repository<ArweaveService>(),
              drivesDao: context.repository<DrivesDao>(),
            ),
          ),
        ],
        child: MaterialApp(
          title: 'Drive',
          theme: appTheme(),
          home: BlocConsumer<ProfileBloc, ProfileState>(
            listener: (context, state) async {
              if (state is ProfilePromptAdd) {
                _promptToAddProfile(context);
              } else if (state is ProfilePromptPassword) {
                final password = await showTextFieldDialog(
                  context,
                  title: 'Unlock profile',
                  fieldLabel: 'Password',
                  confirmingActionLabel: 'UNLOCK',
                  obscureText: true,
                );

                context.bloc<ProfileBloc>().add(ProfileLoad(password));
              }
            },
            builder: (context, state) => state is ProfileLoaded
                ? BlocBuilder<DrivesBloc, DrivesState>(
                    builder: (context, state) {
                      final selectedDriveId = state is DrivesLoadSuccess
                          ? state.selectedDriveId
                          : null;

                      return BlocProvider(
                        key: ValueKey(selectedDriveId),
                        create: (context) => DriveDetailBloc(
                          driveId: selectedDriveId,
                          profileBloc: context.bloc<ProfileBloc>(),
                          uploadBloc: context.bloc<UploadBloc>(),
                          arweave: context.repository<ArweaveService>(),
                          driveDao: context.repository<DriveDao>(),
                        ),
                        child: AppShell(
                          page: BlocBuilder<DrivesBloc, DrivesState>(
                            builder: (context, state) =>
                                state is DrivesLoadSuccess &&
                                        state.selectedDriveId != null
                                    ? DriveDetailView()
                                    : Container(),
                          ),
                        ),
                      );
                    },
                  )
                : Container(),
          ),
        ),
      ),
    );
  }

  void _promptToAddProfile(BuildContext context) async {
    await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AddProfileForm(),
      barrierDismissible: false,
    );
  }
}
