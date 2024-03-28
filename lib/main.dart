import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/activity/activity_cubit.dart';
import 'package:ardrive/blocs/feedback_survey/feedback_survey_cubit.dart';
import 'package:ardrive/blocs/hide/hide_bloc.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_bloc.dart';
import 'package:ardrive/blocs/upload/limits.dart';
import 'package:ardrive/blocs/upload/upload_file_checker.dart';
import 'package:ardrive/components/keyboard_handler.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/core/upload/uploader.dart';
import 'package:ardrive/models/database/database_helpers.dart';
import 'package:ardrive/services/authentication/biometric_authentication.dart';
import 'package:ardrive/services/config/config_fetcher.dart';
import 'package:ardrive/sharing/blocs/sharing_file_bloc.dart';
import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:ardrive/sync/utils/batch_processor.dart';
import 'package:ardrive/theme/theme_switcher_bloc.dart';
import 'package:ardrive/theme/theme_switcher_state.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/repositories/user_repository.dart';
import 'package:ardrive/utils/app_flavors.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/mobile_screen_orientation.dart';
import 'package:ardrive/utils/mobile_status_bar.dart';
import 'package:ardrive/utils/pre_cache_assets.dart';
import 'package:ardrive/utils/secure_key_value_store.dart';
import 'package:ardrive/utils/upload_plan_utils.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_logger/ardrive_logger.dart';
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
import 'package:provider/single_child_widget.dart';
import 'package:pst/pst.dart';

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

    await _initializeServices();

    await _startApp();
  }, (error, stackTrace) {
    logger.e('Error caught.', error, stackTrace);
  });
}

Future<void> _startApp() async {
  final flavor = await configService.loadAppFlavor();

  flavor == Flavor.staging || flavor == Flavor.production
      ? _runWithSentryLogging()
      : _runWithoutLogging();
}

Future<void> _runWithoutLogging() async {
  runApp(const App());
}

Future<void> _runWithSentryLogging() async {
  await initSentry();

  runApp(const App());
}

Future<void> _initializeServices() async {
  final localStore = await LocalKeyValueStore.getInstance();

  await AppInfoServices().loadAppInfo();

  configService = ConfigService(
    appFlavors: AppFlavors(EnvFetcher()),
    configFetcher: ConfigFetcher(localStore: localStore),
  );

  MobileStatusBar.show();
  MobileScreenOrientation.lockInPortraitUp();
  ArDriveMobileDownloader.initialize();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarBrightness: Brightness.light),
  );

  await configService.loadConfig();

  final config = configService.config;

  logger.d('Initializing app with config: $config');

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

  void refreshHTMLPageAtInterval(Duration duration) {
    Timer.periodic(duration, (timer) => triggerHTMLPageReload());
  }

  if (kIsWeb) {
    refreshHTMLPageAtInterval(const Duration(hours: 12));
  }
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
      providers: repositoryProviders,
      child: ArDriveDevToolsShortcuts(
        child: KeyboardHandler(
          child: MultiBlocProvider(
            providers: blocProviders,
            child: BlocConsumer<ThemeSwitcherBloc, ThemeSwitcherState>(
              listener: (context, state) {
                if (state is ThemeSwitcherDarkTheme) {
                  ArDriveUIThemeSwitcher.changeTheme(ArDriveThemes.dark);
                } else if (state is ThemeSwitcherLightTheme) {
                  ArDriveUIThemeSwitcher.changeTheme(ArDriveThemes.light);
                }
              },
              builder: (context, state) {
                return SafeArea(
                  child: ArDriveApp(
                    onThemeChanged: (theme) {
                      context.read<ThemeSwitcherBloc>().add(ChangeTheme());
                    },
                    key: arDriveAppKey,
                    builder: _appBuilder,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  MaterialApp _appBuilder(BuildContext context) {
    final ardriveTheme =
        ArDriveTheme.of(context).themeData.materialThemeData.copyWith(
              scaffoldBackgroundColor:
                  ArDriveTheme.of(context).themeData.backgroundColor,
            );

    return MaterialApp.router(
      title: _appName,
      theme: ardriveTheme,
      debugShowCheckedModeBanner: false,
      routeInformationParser: _routeInformationParser,
      routerDelegate: _routerDelegate,
      localizationsDelegates: _localizationsDelegates,
      supportedLocales: _locales,

      // TODO: Remove this once we have a proper solution for
      builder: (context, child) => ListTileTheme(
        textColor: kOnSurfaceBodyTextColor,
        iconColor: kOnSurfaceBodyTextColor,
        child: Portal(
          child: child!,
        ),
      ),
    );
  }

  static const String _appName = 'ArDrive';

  Iterable<Locale> get _locales => const [
        Locale('en', ''), // English, no country code
        Locale('es', ''), // Spanish, no country code
        Locale.fromSubtags(languageCode: 'zh'), // generic Chinese 'zh'
        Locale.fromSubtags(
          languageCode: 'zh',
          countryCode: 'HK',
        ), // Traditional Chinese, Cantonese
        Locale('ja', ''), // Japanese, no country code
        Locale('hi', ''), // Hindi, no country code
      ];

  Iterable<LocalizationsDelegate> get _localizationsDelegates => const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  List<SingleChildWidget> get blocProviders => [
        ChangeNotifierProvider<ActivityTracker>(
            create: (_) => ActivityTracker()),
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
        BlocProvider(
          create: (context) => PromptToSnapshotBloc(
            userRepository: context.read<UserRepository>(),
            profileCubit: context.read<ProfileCubit>(),
            driveDao: context.read<DriveDao>(),
          ),
        ),
        BlocProvider(
          create: (context) => HideBloc(
            auth: context.read<ArDriveAuth>(),
            uploadPreparationManager: ArDriveUploadPreparationManager(
              uploadPreparePaymentOptions: UploadPaymentEvaluator(
                appConfig: context.read<ConfigService>().config,
                auth: context.read<ArDriveAuth>(),
                turboBalanceRetriever: TurboBalanceRetriever(
                  paymentService: context.read<PaymentService>(),
                ),
                turboUploadCostCalculator: TurboUploadCostCalculator(
                  priceEstimator: TurboPriceEstimator(
                    wallet: context.read<ArDriveAuth>().currentUser.wallet,
                    costCalculator: TurboCostCalculator(
                      paymentService: context.read<PaymentService>(),
                    ),
                    paymentService: context.read<PaymentService>(),
                  ),
                  turboCostCalculator: TurboCostCalculator(
                    paymentService: context.read<PaymentService>(),
                  ),
                ),
                uploadCostEstimateCalculatorForAR:
                    UploadCostEstimateCalculatorForAR(
                  arweaveService: context.read<ArweaveService>(),
                  pstService: context.read<PstService>(),
                  arCostToUsd: ConvertArToUSD(
                    arweave: context.read<ArweaveService>(),
                  ),
                ),
              ),
              uploadPreparer: UploadPreparer(
                uploadPlanUtils: UploadPlanUtils(
                  crypto: ArDriveCrypto(),
                  arweave: context.read<ArweaveService>(),
                  turboUploadService: context.read<TurboUploadService>(),
                  driveDao: context.read<DriveDao>(),
                ),
              ),
            ),
            arweaveService: context.read<ArweaveService>(),
            crypto: ArDriveCrypto(),
            turboUploadService: context.read<TurboUploadService>(),
            driveDao: context.read<DriveDao>(),
            profileCubit: context.read<ProfileCubit>(),
          ),
        ),
        BlocProvider(
          create: (context) => SharingFileBloc(
            context.read<ActivityTracker>(),
          ),
        ),
      ];

  List<SingleChildWidget> get repositoryProviders => [
        RepositoryProvider<ArweaveService>(create: (_) => _arweave),
        // repository provider for UploadFileChecker
        RepositoryProvider<UploadFileSizeChecker>(
          create: (_) => UploadFileSizeChecker(
            fileSizeWarning: fileSizeWarning,
            fileSizeLimit: fileSizeLimit,
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
        RepositoryProvider(
          create: (_) => LicenseService(),
        ),
        RepositoryProvider(
          create: (_) => SyncRepository(
            arweave: _arweave,
            configService: configService,
            driveDao: _.read<DriveDao>(),
            licenseService: _.read<LicenseService>(),
            batchProcessor: BatchProcessor(),
          ),
        ),
      ];
}
