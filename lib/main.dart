import 'package:ardrive/blocs/activity/activity_cubit.dart';
import 'package:ardrive/blocs/feedback_survey/feedback_survey_cubit.dart';
import 'package:ardrive/utils/html/html_util.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_portal/flutter_portal.dart';

// import 'package:flutter_webview_plugin/flutter_webview_plugin.dart';

import 'blocs/blocs.dart';
import 'models/models.dart';
import 'pages/pages.dart';
import 'services/services.dart';
import 'theme/theme.dart';

// final flutterWebViewPlugin = FlutterWebviewPlugin();

late PST pst;

getPSTFromURl() {
  // flutterWebViewPlugin.onUrlChanged.listen((String state) async {
  //   print(state);
  //   if (state.contains('loaded-pst')) {
  //     final uri = Uri.parse(state.split('/').last);
  //     final params = uri.queryParameters;
  //     pst = PST(double.parse(params['fee']!), params['weightedPstHolder']!);
  //     print(pst.fee);
  //     print(pst.weightedPstHolder);

  //     // do whatever you want
  //   }
  // });
}

class PST {
  double fee;
  String weightedPstHolder;

  PST(this.fee, this.weightedPstHolder);
}

late ConfigService configService;
late AppConfig config;
late ArweaveService arweave;
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  configService = ConfigService();
  config = await configService.getConfig();

  // flutterWebViewPlugin
  //     .launch('https://ardrive-web--pr547-mobile-pst-test-9x2r4j2c.web.app/',
  //         hidden: true)
  //     .then((value) {
  //   getPSTFromURl();
  // });
  pst = PST(0.15, '-8A6RexFkpfWwuyVO98wzSFZh0d6VJuI-buTJvlwOJQ');

  arweave = ArweaveService(
      Arweave(gatewayUrl: Uri.parse(config.defaultArweaveGatewayUrl!)));
  refreshHTMLPageAtInterval(const Duration(hours: 12));
  runApp(App());
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
            BlocProvider(
              create: (context) =>
                  FeedbackSurveyCubit(FeedbackSurveyInitialState()),
            ),
          ],
          child: MaterialApp.router(
            title: 'ArDrive',
            theme: appTheme(),
            debugShowCheckedModeBanner: false,
            routeInformationParser: _routeInformationParser,
            routerDelegate: _routerDelegate,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('en', ''), // English, no country code
              Locale('es', ''), // Spanish, no country code
              Locale('zh', ''), // Chinese (Mandarin), no country code
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
