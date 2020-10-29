import 'package:arweave/arweave.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'app_shell.dart';
import 'blocs/blocs.dart';
import 'models/models.dart';
import 'services/services.dart';
import 'theme/theme.dart';
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
  Widget build(BuildContext context) => MultiRepositoryProvider(
        providers: [
          RepositoryProvider<ArweaveService>(create: (_) => arweave),
          RepositoryProvider<AppConfig>(create: (_) => config),
          RepositoryProvider<ProfileDao>(create: (_) => db.profileDao),
          RepositoryProvider<DrivesDao>(create: (_) => db.drivesDao),
          RepositoryProvider<DriveDao>(create: (_) => db.driveDao),
        ],
        child: BlocProvider(
          create: (context) => ProfileCubit(
            arweave: context.repository<ArweaveService>(),
            profileDao: context.repository<ProfileDao>(),
          ),
          child: BlocBuilder<ProfileCubit, ProfileState>(
            builder: (context, state) {
              Widget view;
              if (state is! ProfileLoaded) {
                view = ProfileAuthView();
              } else {
                view = BlocBuilder<DrivesCubit, DrivesState>(
                  builder: (context, state) {
                    if (state is DrivesLoadSuccess) {
                      return BlocProvider(
                        key: ValueKey(state.selectedDriveId),
                        create: (context) => DriveDetailCubit(
                          driveId: state.selectedDriveId,
                          profileCubit: context.bloc<ProfileCubit>(),
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
                );
              }

              final app = ListTileTheme(
                textColor: kOnSurfaceBodyTextColor,
                iconColor: kOnSurfaceBodyTextColor,
                child: MaterialApp(
                  title: 'ArDrive',
                  theme: appTheme(),
                  home: view,
                ),
              );

              if (state is! ProfileLoaded) {
                return app;
              } else {
                return MultiBlocProvider(
                  providers: [
                    BlocProvider(
                      create: (context) => UploadBloc(
                        profileCubit: context.bloc<ProfileCubit>(),
                        arweave: context.repository<ArweaveService>(),
                        driveDao: context.repository<DriveDao>(),
                      ),
                    ),
                    BlocProvider(
                      create: (context) => SyncCubit(
                        profileCubit: context.bloc<ProfileCubit>(),
                        arweave: context.repository<ArweaveService>(),
                        drivesDao: context.repository<DrivesDao>(),
                        driveDao: context.repository<DriveDao>(),
                        db: db,
                      ),
                    ),
                    BlocProvider(
                      create: (context) => DrivesCubit(
                        profileCubit: context.bloc<ProfileCubit>(),
                        drivesDao: context.repository<DrivesDao>(),
                      ),
                    ),
                  ],
                  child: app,
                );
              }
            },
          ),
        ),
      );
}
