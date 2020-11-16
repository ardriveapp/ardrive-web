import 'package:arweave/arweave.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_portal/flutter_portal.dart';

import 'blocs/blocs.dart';
import 'models/models.dart';
import 'pages/pages.dart';
import 'services/services.dart';
import 'theme/theme.dart';

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
  final _routerDelegate = AppRouterDelegate();
  final _routeInformationParser = AppRouteInformationParser();

  @override
  Widget build(BuildContext context) => MultiRepositoryProvider(
        providers: [
          RepositoryProvider<ArweaveService>(create: (_) => arweave),
          RepositoryProvider<PstService>(create: (_) => PstService()),
          RepositoryProvider<AppConfig>(create: (_) => config),
          RepositoryProvider<ProfileDao>(create: (_) => db.profileDao),
          RepositoryProvider<DrivesDao>(create: (_) => db.drivesDao),
          RepositoryProvider<DriveDao>(create: (_) => db.driveDao),
        ],
        child: BlocProvider(
          create: (context) => ProfileCubit(
            arweave: context.read<ArweaveService>(),
            profileDao: context.read<ProfileDao>(),
          ),
          child: BlocBuilder<ProfileCubit, ProfileState>(
            builder: (context, state) => MaterialApp.router(
              title: 'ArDrive',
              theme: appTheme(),
              routeInformationParser: _routeInformationParser,
              routerDelegate: _routerDelegate,
              builder: (context, child) {
                final content = ListTileTheme(
                  textColor: kOnSurfaceBodyTextColor,
                  iconColor: kOnSurfaceBodyTextColor,
                  child: Portal(
                    child: child,
                  ),
                );

                if (state is! ProfileLoaded) {
                  return content;
                } else {
                  return BlocProvider(
                    create: (context) => SyncCubit(
                      profileCubit: context.read<ProfileCubit>(),
                      arweave: context.read<ArweaveService>(),
                      drivesDao: context.read<DrivesDao>(),
                      driveDao: context.read<DriveDao>(),
                      db: db,
                    ),
                    child: BlocListener<SyncCubit, SyncState>(
                      listener: (context, state) {
                        if (state is SyncFailure) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to sync drive contents.'),
                              action: SnackBarAction(
                                label: 'TRY AGAIN',
                                onPressed: () =>
                                    context.read<SyncCubit>().startSync(),
                              ),
                            ),
                          );
                        }
                      },
                      child: content,
                    ),
                  );
                }
              },
            ),
          ),
        ),
      );
}
