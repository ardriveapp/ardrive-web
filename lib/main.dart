import 'dart:html' as html;

import 'package:ardrive/blocs/activity/activity_cubit.dart';
import 'package:ardrive/utils/html/html_util.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_portal/flutter_portal.dart';

import 'blocs/blocs.dart';
import 'models/models.dart';
import 'pages/pages.dart';
import 'services/services.dart';
import 'theme/theme.dart';

late ConfigService configService;
late AppConfig config;
late ArweaveService arweave;
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  configService = ConfigService();
  config = await configService.getConfig();

  arweave = ArweaveService(
      Arweave(gatewayUrl: Uri.parse(config.defaultArweaveGatewayUrl!)));
  refreshHTMLPageAtInterval(Duration(hours: 12));
  runApp(App());
}

class LoadPSTApp extends StatefulWidget {
  const LoadPSTApp({Key? key}) : super(key: key);

  @override
  State<LoadPSTApp> createState() => _LoadPSTAppState();
}

class _LoadPSTAppState extends State<LoadPSTApp> {
  void _loadPST() async {
    PstService pstService = PstService();

    final fee = await pstService.getPstFeePercentage();
    final weightedPstHolder = await pstService.getWeightedPstHolder();

    print(fee);

    html.window.location.href =
        'https://app.ardrive.io/#/loaded-pst/fee=$fee&weightedPstHolder=$weightedPstHolder';
  }

  @override
  void initState() {
    _loadPST();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class App extends StatefulWidget {
  @override
  _AppState createState() => _AppState();
}

class _AppState extends State<App> {
  final _routerDelegate = AppRouterDelegate();
  final _routeInformationParser = AppRouteInformationParser();

  @override
  Widget build(BuildContext context) => MultiRepositoryProvider(
        providers: [
          RepositoryProvider<ArweaveService>(create: (_) => arweave),
          RepositoryProvider<PstService>(create: (_) => PstService()),
          RepositoryProvider<AppConfig>(create: (_) => config),
          RepositoryProvider<Database>(create: (_) => Database()),
          RepositoryProvider<ProfileDao>(
              create: (context) => context.read<Database>().profileDao),
          RepositoryProvider<DriveDao>(
              create: (context) => context.read<Database>().driveDao),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (context) => ProfileCubit(
                arweave: context.read<ArweaveService>(),
                profileDao: context.read<ProfileDao>(),
                db: context.read<Database>(),
              ),
            ),
            BlocProvider(
              create: (context) => ActivityCubit(),
            ),
          ],
          child: MaterialApp.router(
            title: 'ArDrive',
            theme: appTheme(),
            debugShowCheckedModeBanner: false,
            routeInformationParser: _routeInformationParser,
            routerDelegate: _routerDelegate,
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: [
              const Locale('en', ''), // English, no country code
              const Locale('es', ''), // Spanish, no country code
            ],
            builder: (context, child) => ListTileTheme(
              textColor: kOnSurfaceBodyTextColor,
              iconColor: kOnSurfaceBodyTextColor,
              child: Portal(
                child: child!,
              ),
            ),
          ),
        ),
      );
}
