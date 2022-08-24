import 'dart:io';

import 'package:ardrive/blocs/activity/activity_cubit.dart';
import 'package:ardrive/blocs/feedback_survey/feedback_survey_cubit.dart';
import 'package:ardrive/pst/ardrive_contract_oracle.dart';
import 'package:ardrive/pst/community_oracle.dart';
import 'package:ardrive/pst/contract_oracle.dart';
import 'package:ardrive/pst/contract_readers/redstone_contract_reader.dart';
import 'package:ardrive/pst/contract_readers/smartweave_contract_reader.dart';
import 'package:ardrive/pst/contract_readers/verto_contract_reader.dart';
import 'package:ardrive/services/analytics/ardrive_analytics.dart';
import 'package:ardrive/services/analytics/compound_adrive_analytics.dart';
import 'package:ardrive/services/analytics/firebase_ardrive_analytics.dart';
import 'package:ardrive/services/analytics/logger_ardrive_analytics.dart';
import 'package:ardrive/services/analytics/pendo_analytics.dart';
import 'package:ardrive/utils/html/html_util.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:arweave/arweave.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:pendo_sdk/pendo_sdk.dart';

import 'blocs/blocs.dart';
import 'firebase_options.dart';
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
  config = await configService.getConfig(
    localStore: await LocalKeyValueStore.getInstance(),
  );

  if (!kIsWeb) {
    late String pendoKey;
    if (Platform.isAndroid) {
      pendoKey = 'REPLACE_WITH_ANDROID_KEY';
    } else if (Platform.isIOS) {
      pendoKey = 'REPLACE_WITH_IOS_KEY';
    } else {
      throw PlatformException(code: Platform.operatingSystem);
    }

    await PendoFlutterPlugin.setup(pendoKey);
  }

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  arweave = ArweaveService(
      Arweave(gatewayUrl: Uri.parse(config.defaultArweaveGatewayUrl!)));
  refreshHTMLPageAtInterval(const Duration(hours: 12));
  runApp(const App());
}

class App extends StatefulWidget {
  const App({Key? key}) : super(key: key);

  @override
  AppState createState() => AppState();
}

class AppState extends State<App> {
  final _routerDelegate = AppRouterDelegate();
  final _routeInformationParser = AppRouteInformationParser();

  @override
  Widget build(BuildContext context) => MultiRepositoryProvider(
        providers: [
          RepositoryProvider<ArweaveService>(create: (_) => arweave),
          RepositoryProvider<PstService>(
            create: (_) => PstService(
              communityOracle: CommunityOracle(
                ArDriveContractOracle([
                  ContractOracle(RedstoneContractReader()),
                  ContractOracle(VertoContractReader()),
                  ContractOracle(SmartweaveContractReader()),
                ]),
              ),
            ),
          ),
          RepositoryProvider<AppConfig>(create: (_) => config),
          RepositoryProvider<Database>(create: (_) => Database()),
          RepositoryProvider<ProfileDao>(
              create: (context) => context.read<Database>().profileDao),
          RepositoryProvider<DriveDao>(
              create: (context) => context.read<Database>().driveDao),
          RepositoryProvider<ArDriveAnalytics>(
              create: (_) => CompoundArDriveAnalytics([
                    FirebaseArDriveAnalytics(),
                    LoggerArDriveAnalytics(),
                    PendoAnalytics()
                  ])),
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
              Locale.fromSubtags(languageCode: 'zh'), // generic Chinese 'zh'
              Locale.fromSubtags(
                languageCode: 'zh',
                countryCode: 'HK',
              ), // generic traditional Chinese 'zh_Hant'
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
