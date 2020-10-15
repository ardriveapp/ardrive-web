import 'package:ardrive/theme/theme.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'app_shell.dart';
import 'blocs/blocs.dart';
import 'models/models.dart';
import 'services/services.dart';
import 'views/views.dart';

ConfigService configService;
AppConfig config;
ArweaveService arweave;
Database db;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  configService = ConfigService();
  config = await configService.getConfig();

  arweave = ArweaveService(
      Arweave(gatewayUrl: Uri.parse(config.defaultArweaveGatewayUrl)));

  db = Database();

  runApp(App());
}

class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<ArweaveService>(create: (_) => arweave),
        RepositoryProvider<AppConfig>(create: (_) => config),
        RepositoryProvider<ProfileDao>(create: (_) => db.profileDao),
        RepositoryProvider<DrivesDao>(create: (_) => db.drivesDao),
        RepositoryProvider<DriveDao>(create: (_) => db.driveDao),
      ],
      child: BlocProvider(
        create: (context) => ProfileBloc(
          profileDao: context.repository<ProfileDao>(),
        ),
        child: MaterialApp(
          title: 'ArDrive',
          theme: appTheme(),
          home: BlocBuilder<ProfileBloc, ProfileState>(
            builder: (context, state) {
              if (state is ProfileUnavailable) {
                return ProfileAuthView();
              } else if (state is ProfileLoading) {
                return Container();
              } else if (state is ProfileLoaded) {
                return MultiBlocProvider(
                  providers: [
                    BlocProvider(
                      create: (context) => UploadBloc(
                        profileBloc: context.bloc<ProfileBloc>(),
                        arweave: context.repository<ArweaveService>(),
                        driveDao: context.repository<DriveDao>(),
                      ),
                    ),
                    BlocProvider(
                      create: (context) => SyncCubit(
                        profileBloc: context.bloc<ProfileBloc>(),
                        arweave: context.repository<ArweaveService>(),
                        drivesDao: context.repository<DrivesDao>(),
                        driveDao: context.repository<DriveDao>(),
                        db: db,
                      ),
                    ),
                    BlocProvider(
                      create: (context) => DrivesCubit(
                        profileBloc: context.bloc<ProfileBloc>(),
                        drivesDao: context.repository<DrivesDao>(),
                      ),
                    ),
                  ],
                  child: BlocBuilder<DrivesCubit, DrivesState>(
                    builder: (context, state) {
                      if (state is DrivesLoadSuccess) {
                        return BlocProvider(
                          key: ValueKey(state.selectedDriveId),
                          create: (context) => DriveDetailCubit(
                            driveId: state.selectedDriveId,
                            profileBloc: context.bloc<ProfileBloc>(),
                            uploadBloc: context.bloc<UploadBloc>(),
                            driveDao: context.repository<DriveDao>(),
                            config: context.repository<AppConfig>(),
                          ),
                          child: AppShell(
                            page: state.selectedDriveId != null
                                ? DriveDetailView()
                                : Container(),
                          ),
                        );
                      } else {
                        return Container();
                      }
                    },
                  ),
                );
              } else {
                return Container();
              }
            },
          ),
        ),
      ),
    );
  }
}
