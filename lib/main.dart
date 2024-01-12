import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/activity/activity_cubit.dart';
import 'package:ardrive/blocs/feedback_survey/feedback_survey_cubit.dart';
import 'package:ardrive/blocs/upload/limits.dart';
import 'package:ardrive/blocs/upload/upload_file_checker.dart';
import 'package:ardrive/components/keyboard_handler.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/database/database_helpers.dart';
import 'package:ardrive/services/authentication/biometric_authentication.dart';
import 'package:ardrive/services/config/config_fetcher.dart';
import 'package:ardrive/theme/theme_switcher_bloc.dart';
import 'package:ardrive/theme/theme_switcher_state.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/repositories/user_repository.dart';
import 'package:ardrive/utils/app_flavors.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/mobile_screen_orientation.dart';
import 'package:ardrive/utils/mobile_status_bar.dart';
import 'package:ardrive/utils/pre_cache_assets.dart';
import 'package:ardrive/utils/secure_key_value_store.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import 'package:pst/pst.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'blocs/blocs.dart';
import 'models/models.dart';
import 'pages/pages.dart';
import 'services/services.dart';
import 'theme/theme.dart';

final overlayKey = GlobalKey<OverlayState>();

late ConfigService configService;
late ArweaveService _arweave;
late TurboUploadService _turboUpload;
late PaymentService _turboPayment;
void main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    final localStore = await LocalKeyValueStore.getInstance();

    await AppInfoServices().loadAppInfo();

    configService = ConfigService(
      appFlavors: AppFlavors(EnvFetcher()),
      configFetcher: ConfigFetcher(localStore: localStore),
    );

    await configService.loadConfig();

    final flavor = await configService.loadAppFlavor();

    await _initialize();

    if (flavor == Flavor.development) {
      _runWithCrashlytics();
      return;
    }

    logger.d('Starting without crashlytics');

    _runWithoutCrashlytics();
  }, (error, stackTrace) async {
    _runWithoutCrashlytics();
  });
}

Future<void> _runWithoutCrashlytics() async {
  await _initialize();
  runApp(const App());
}

Future<void> _initialize() async {
  MobileStatusBar.show();
  MobileScreenOrientation.lockInPortraitUp();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarBrightness: Brightness.light),
  );

  final config = configService.config;

  logger.d('Initializing app with config: $config');

  ArDriveMobileDownloader.initialize();

  _arweave = ArweaveService(
    Arweave(
      gatewayUrl: Uri.parse(config.defaultArweaveGatewayUrl!),
    ),
    ArDriveCrypto(),
  );
  _turboUpload = config.useTurboUpload
      ? TurboUploadService(
          tabVisibilitySingleton: TabVisibilitySingleton(),
          turboUploadUri: Uri.parse(config.defaultTurboUploadUrl!),
          allowedDataItemSize: config.allowedDataItemSizeForTurbo,
          httpClient: ArDriveHTTP(),
        )
      : DontUseUploadService();

  _turboPayment = PaymentService(
    turboPaymentUri: Uri.parse(config.defaultTurboPaymentUrl!),
    httpClient: ArDriveHTTP(),
  );

  if (kIsWeb) {
    refreshHTMLPageAtInterval(const Duration(hours: 12));
  }
}

Future<void> _runWithCrashlytics() async {
  await SentryFlutter.init(
    (options) {
      options.tracesSampleRate = 1.0;
    },
  );

  runApp(const App());
}

void refreshHTMLPageAtInterval(Duration duration) {
  Timer.periodic(duration, (timer) => triggerHTMLPageReload());
}

class App extends StatefulWidget {
  const App({Key? key}) : super(key: key);

  @override
  AppState createState() => AppState();
}

class AppState extends State<App> {
  final AppRouterDelegate _routerDelegate = AppRouterDelegate();
  final _routeInformationParser = AppRouteInformationParser();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      preCacheLoginAssets(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        ChangeNotifierProvider<ActivityTracker>(
            create: (_) => ActivityTracker()),
        RepositoryProvider<ArweaveService>(create: (_) => _arweave),
        // repository provider for UploadFileChecker
        RepositoryProvider<UploadFileChecker>(
          create: (_) => UploadFileChecker(
            privateFileSafeSizeLimit:
                kIsWeb ? privateFileSizeLimit : mobilePrivateFileSizeLimit,
            publicFileSafeSizeLimit: publicFileSafeSizeLimit,
          ),
        ),
        RepositoryProvider<ArweaveService>(create: (_) => _arweave),
        RepositoryProvider<ConfigService>(
          create: (_) => configService,
        ),
        RepositoryProvider<TurboUploadService>(
          create: (_) => _turboUpload,
        ),
        RepositoryProvider<PaymentService>(
          create: (_) => _turboPayment,
        ),
        RepositoryProvider<PstService>(
          create: (_) => PstService(
            communityOracle: CommunityOracle(
              ArDriveContractOracle(
                [
                  ContractOracle(ARNSContractReader()),
                ],
                fallbackContractOracle: ContractOracle(
                  WarpContractReader(),
                ),
              ),
            ),
          ),
        ),
        RepositoryProvider<BiometricAuthentication>(
          create: (_) => BiometricAuthentication(
            LocalAuthentication(),
            SecureKeyValueStore(
              const FlutterSecureStorage(),
            ),
          ),
        ),
        RepositoryProvider<Database>(create: (_) => Database()),
        RepositoryProvider<ProfileDao>(
            create: (context) => context.read<Database>().profileDao),
        RepositoryProvider<DriveDao>(
            create: (context) => context.read<Database>().driveDao),
        RepositoryProvider<UserRepository>(
          create: (context) => UserRepository(
            context.read<ProfileDao>(),
            context.read<ArweaveService>(),
          ),
        ),
        RepositoryProvider(
          create: (context) => ArDriveAuth(
            databaseHelpers: DatabaseHelpers(
              context.read<Database>(),
            ),
            arConnectService: ArConnectService(),
            biometricAuthentication: context.read<BiometricAuthentication>(),
            secureKeyValueStore: SecureKeyValueStore(
              const FlutterSecureStorage(),
            ),
            crypto: ArDriveCrypto(),
            arweave: _arweave,
            userRepository: context.read<UserRepository>(),
          ),
        ),
        RepositoryProvider(
          create: (_) => UserPreferencesRepository(
            themeDetector: ThemeDetector(),
          ),
        ),
      ],
      child: ArDriveDevToolsShortcuts(
        child: KeyboardHandler(
          child: MultiBlocProvider(
            providers: [
              BlocProvider(
                create: (context) => ThemeSwitcherBloc(
                  userPreferencesRepository:
                      context.read<UserPreferencesRepository>(),
                )..add(LoadTheme()),
              ),
              BlocProvider(
                create: (context) => ProfileCubit(
                  arweave: context.read<ArweaveService>(),
                  turboUploadService: context.read<TurboUploadService>(),
                  profileDao: context.read<ProfileDao>(),
                  db: context.read<Database>(),
                  tabVisibilitySingleton: TabVisibilitySingleton(),
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
            child: BlocConsumer<ThemeSwitcherBloc, ThemeSwitcherState>(
              listener: (context, state) {
                if (state is ThemeSwitcherDarkTheme) {
                  ArDriveUIThemeSwitcher.changeTheme(ArDriveThemes.dark);
                } else if (state is ThemeSwitcherLightTheme) {
                  ArDriveUIThemeSwitcher.changeTheme(ArDriveThemes.light);
                }
              },
              builder: (context, state) {
                return ArDriveApp(
                  onThemeChanged: (theme) {
                    context.read<ThemeSwitcherBloc>().add(ChangeTheme());
                  },
                  key: arDriveAppKey,
                  builder: (context) => MaterialApp.router(
                    title: 'ArDrive',
                    theme: ArDriveTheme.of(context)
                        .themeData
                        .materialThemeData
                        .copyWith(
                          scaffoldBackgroundColor: ArDriveTheme.of(context)
                              .themeData
                              .backgroundColor,
                        ),
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
                      Locale.fromSubtags(
                          languageCode: 'zh'), // generic Chinese 'zh'
                      Locale.fromSubtags(
                        languageCode: 'zh',
                        countryCode: 'HK',
                      ), // Traditional Chinese, Cantonese
                      Locale('ja', ''), // Japanese, no country code
                      Locale('hi', ''), // Hindi, no country code
                    ],
                    builder: (context, child) => ListTileTheme(
                      textColor: kOnSurfaceBodyTextColor,
                      iconColor: kOnSurfaceBodyTextColor,
                      child: Portal(
                        child: child!,
                      ),
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
