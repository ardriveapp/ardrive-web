import 'dart:async';

import 'package:ardrive/core/upload/metadata_write_cost.dart';
import 'package:ardrive/components/drive_fingerprint.dart';
import 'package:ardrive/locked_drives/domain/drive_unlock_session.dart';
import 'package:ardrive/locked_drives/domain/drive_unlocker.dart';
import 'package:ardrive/authentication/password/new_password.dart';
import 'package:ardrive/arns/data/arns_names_repository.dart';
import 'package:ardrive/arns/data/arns_pending_action_store.dart';
import 'package:ardrive/arns/data/arns_wallet_store.dart';
import 'package:ardrive/arns/data/turbo_arns_action_client.dart';
import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/arns/presentation/names/arns_names_cubit.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/activity/activity_cubit.dart';
import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/blocs/hide/hide_bloc.dart';
import 'package:ardrive/blocs/profile/profile_presence_hint.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_bloc.dart';
import 'package:ardrive/blocs/upload/limits.dart';
import 'package:ardrive/blocs/upload/upload_file_checker.dart';
import 'package:ardrive/components/keyboard_handler.dart';
import 'package:ardrive/components/nav_sections.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/core/arfs/repository/file_repository.dart';
import 'package:ardrive/core/arfs/repository/folder_repository.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/download/ardrive_downloader.dart';
import 'package:ardrive/drive_explorer/thumbnail/repository/thumbnail_repository.dart';
import 'package:ardrive/publication/data/download_helper.dart';
import 'package:ardrive/publication/data/publication_meta_reader.dart';
import 'package:ardrive/publication/data/publication_repository.dart';
import 'package:ardrive/publication/domain/publication_mode.dart';
import 'package:ardrive/publication/presentation/publications_cubit.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/models/database/database_helpers.dart';
import 'package:ardrive/pages/database_unavailable/database_unavailable_app.dart';
import 'package:ardrive/permanence/permanence_cache.dart';
import 'package:ardrive/services/authentication/biometric_authentication.dart';
import 'package:ardrive/services/config/config_fetcher.dart';
import 'package:ardrive/shared/blocs/banner/app_banner_bloc.dart';
import 'package:ardrive/sharing/blocs/sharing_file_bloc.dart';
import 'package:ardrive/sync/data/snapshot_validation_service.dart';
import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:ardrive/sync/utils/batch_processor.dart';
import 'package:ardrive/theme/theme_switcher_bloc.dart';
import 'package:ardrive/theme/theme_switcher_state.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/turbo/utils/get_signature_headers_for_turbo.dart';
import 'package:ardrive/user/name/domain/repository/profile_logo_repository.dart';
import 'package:ardrive/user/name/presentation/bloc/profile_name_bloc.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/repositories/user_repository.dart';
import 'package:ardrive/web_pages/presentation/web_pages_cubit.dart';
import 'package:ardrive/utils/app_flavors.dart';
import 'package:ardrive/utils/app_url_strategy.dart';
import 'package:ardrive/utils/dependency_injection_utils.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/mobile_screen_orientation.dart';
import 'package:ardrive/utils/mobile_status_bar.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/pre_cache_assets.dart';
import 'package:ardrive/utils/secure_key_value_store.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:ario_sdk/ario_sdk.dart';
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
late ArweaveService arweave;
late TurboUploadService _turboUpload;
late PaymentService _turboPayment;
late Database db;

/// The session's private-drive state - locked drives, wallet signatures - and
/// what opens them. One of each, shared by sign-in, drive discovery and the
/// unlock dialog. See `lib/locked_drives/`.
late DriveUnlocker driveUnlocker;
late final LocalKeyValueStore localKeyValueStore;
late final ProfilePresenceHint _profilePresenceHint;

void main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    registerWordlistLicense();
    FingerprintEmojiFont.registerLicense();

    // Before anything can read a route. Hash routing (the default) leaves the
    // engine's own strategy in place, so this is a no-op today - see
    // `lib/utils/app_url_strategy.dart` for what has to land before it is not.
    configureAppUrlStrategy();

    // Before any service starts: a publication starts them differently
    // (docs/PUBLICATIONS.md, "How a page opens").
    PublicationMode.detect(readPublicationMetaContent,
        readTitle: readPageTitle);
    if (PublicationMode.isOn) {
      PlausibleEventTracker.disabled = true;
    }

    await _initializeServices();

    await _startApp();
  }, (error, stackTrace) async {
    logger.e('Error caught.', error, stackTrace);
    logger.d('Error: ${error.toString()}');
  });
}

Future<void> _startApp() async {
  runApp(const App());
  if (kIsWeb && !PublicationMode.isOn) unawaited(_replaceAppIfDatabaseFails());
}

/// Shows [DatabaseUnavailableApp] in place of the app if the database will
/// not open or migrate.
///
/// The database starts opening before `runApp` (`_initializeServices`), and
/// no screen after the sign-in page can show without it. Waited for
/// alongside the app rather than before it, so a sound database opens no
/// later than it did. Web only: Try again reloads the page. Nothing there
/// deletes or changes the data.
Future<void> _replaceAppIfDatabaseFails() async {
  final failure = await db.openFailure();
  if (failure == null) return;
  logger.e('The database did not open', failure);
  // The theme the app would have shown, read as UserPreferencesRepository
  // reads it: that repository is part of what could not start.
  final theme = localKeyValueStore.getString('currentTheme') ??
      ThemeDetector().getOSDefaultTheme().name;
  runApp(DatabaseUnavailableApp(
    dark: theme == ArDriveThemes.dark.name,
    onTryAgain: triggerHTMLPageReload,
    onHelpCenter: () => openUrl(url: Resources.helpCenterLink),
    onShareLogs: (info) => logger.exportLogs(info: info),
  ));
}

Future<void> _initializeServices() async {
  // The app's version, a fetch of version.json on the web. Not awaited: only
  // uploads, licences and Help read it, all well after the first frame, and
  // the sign-in page should not wait a round trip for it.
  unawaited(AppInfoServices().loadAppInfo().catchError(
      (Object e, StackTrace s) =>
          logger.e('Could not read the app version', e, s)));

  localKeyValueStore = await LocalKeyValueStore.getInstance();

  // Before the config below writes to the store: an empty store is a
  // browser that has never run the app.
  _profilePresenceHint = ProfilePresenceHint(localKeyValueStore);

  // Opening the database (its worker, sqlite3.wasm, the schema) is most of
  // what a start waits for, and needs nothing below, so it starts now, beside
  // the config. Left to the first read, it began only after the first frame,
  // the heaviest of the start, had been built. Failures are handled after
  // runApp, as before (_replaceAppIfDatabaseFails).
  db = PublicationMode.isOn ? Database.forPublication() : Database();
  if (kIsWeb && !PublicationMode.isOn) unawaited(db.openFailure());

  // The pictures the sign-in page paints first, for a start that shows it.
  if (!PublicationMode.isOn && !_opensALinkPage(Uri.base)) {
    final theme = localKeyValueStore.getString('currentTheme') ??
        ThemeDetector().getOSDefaultTheme().name;
    preCacheFirstLoginAssets(light: theme == ArDriveThemes.light.name);
  }

  // Mobile UI setup (non-blocking, fire-and-forget)
  MobileStatusBar.show();
  MobileScreenOrientation.lockInPortraitUp();
  ArDriveMobileDownloader.initialize();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarBrightness: Brightness.light),
  );

  // Config depends on localKeyValueStore
  configService = ConfigService(
    appFlavors: AppFlavors(EnvFetcher()),
    configFetcher: ConfigFetcher(
      localStore: localKeyValueStore,
      publicationMode: PublicationMode.isOn,
    ),
  );

  await configService.loadConfig();

  final config = configService.config;

  // Apply any persisted Solana RPC / program ID overrides from dev tools. A
  // publication reads no stored config and has no use for Solana.
  if (!PublicationMode.isOn &&
      (config.solanaRpcUrl != null ||
          config.solanaCoreProgramId != null ||
          config.solanaGarProgramId != null ||
          config.solanaArnsProgramId != null ||
          config.solanaAntProgramId != null)) {
    await ArioSDKFactory().create().reinitialize(
          rpcUrl: config.solanaRpcUrl,
          coreProgramId: config.solanaCoreProgramId,
          garProgramId: config.solanaGarProgramId,
          arnsProgramId: config.solanaArnsProgramId,
          antProgramId: config.solanaAntProgramId,
        );
  }

  if (PublicationMode.isOn) {
    useGatewayForDownloadHelper(
        Uri.parse(config.arweaveGatewayForDataRequest.url));
  }

  arweave = ArweaveService(
    Arweave(
      api: ArweaveApi(
        gatewayUrl: Uri.parse(config.arweaveGatewayForDataRequest.url),
      ),
    ),
    ArDriveCrypto(),
    db.driveDao,
    configService,
  );

  driveUnlocker = DriveUnlocker(
    crypto: ArDriveCrypto(),
    arweave: arweave,
    driveDao: db.driveDao,
    session: DriveUnlockSession(),
  );
  // A publication uploads nothing, and a live service would ask Turbo for
  // its limits as soon as it is built.
  _turboUpload = config.useTurboUpload && !PublicationMode.isOn
      ? TurboUploadService(
          turboUploadUri: Uri.parse(config.defaultTurboUploadUrl!),
          allowedDataItemSize: config.allowedDataItemSizeForTurbo,
          httpClient: ArDriveHTTP(),
        )
      : DontUseUploadService();

  _turboPayment = PaymentService(
    turboPaymentUri: Uri.parse(config.defaultTurboPaymentUrl!),
    httpClient: ArDriveHTTP(),
    turboSignatureHeadersManager: TurboSignatureHeadersManager.getInstance(
      tabVisibility: TabVisibilitySingleton(),
    ),
  );

  void refreshHTMLPageAtInterval(Duration duration) {
    Timer.periodic(duration, (timer) => triggerHTMLPageReload());
  }

  // A publication runs the release it pins, for good: a reload changes
  // nothing, so it never reloads itself.
  if (kIsWeb && !PublicationMode.isOn) {
    refreshHTMLPageAtInterval(const Duration(hours: 12));
  }
}

/// Whether [uri] opens a page for someone who was sent a link (a shared
/// file, a raw transaction), which never shows the sign-in page.
bool _opensALinkPage(Uri uri) {
  final route = uri.fragment;
  return route.startsWith('/file/') ||
      route.startsWith('/view/') ||
      route.startsWith('/share/');
}

class App extends StatefulWidget {
  const App({super.key});

  @override
  AppState createState() => AppState();
}

class AppState extends State<App> {
  final AppRouterDelegate _routerDelegate = AppRouterDelegate();
  final _routeInformationParser = AppRouteInformationParser();

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
      // A publication keeps the title its publisher wrote.
      title: PublicationMode.pageTitle ?? _appName,
      theme: ardriveTheme,
      debugShowCheckedModeBanner: false,
      routeInformationParser: _routeInformationParser,
      routerDelegate: _routerDelegate,
      localizationsDelegates: _localizationsDelegates,
      supportedLocales: _locales,

      // A list tile with no colours of its own takes the theme's text and
      // icon colours, in both themes.
      builder: (context, child) => ListTileTheme(
        textColor: ArDriveTheme.of(context).themeData.colorTokens.textHigh,
        iconColor: ArDriveTheme.of(context).themeData.colorTokens.iconHigh,
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
        // Above the router, which builds a sidebar per page: see the cubit.
        BlocProvider(
          create: (context) => NavSectionsCubit(
            preferences: context.read<UserPreferencesRepository>(),
          ),
        ),
        BlocProvider(
          create: (context) => GlobalHideBloc(
            userPreferencesRepository:
                context.read<UserPreferencesRepository>(),
            driveDao: context.read<DriveDao>(),
          ),
        ),
        BlocProvider(
          create: (context) => ThemeSwitcherBloc(
            userPreferencesRepository:
                context.read<UserPreferencesRepository>(),
          )..add(LoadTheme()),
        ),
        BlocProvider(
          create: (context) => ProfileCubit(
            turboUploadService: context.read<TurboUploadService>(),
            profileDao: context.read<ProfileDao>(),
            db: context.read<Database>(),
            tabVisibilitySingleton: TabVisibilitySingleton(),
            arDriveAuth: context.read<ArDriveAuth>(),
            presenceHint: _profilePresenceHint,
          ),
        ),
        BlocProvider(
          create: (context) => ActivityCubit(),
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
            costReader: MetadataWriteCostReader(
              payments: context.read<PaymentService>(),
              turbo: context.read<TurboUploadService>(),
              arweave: context.read<ArweaveService>(),
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
        BlocProvider<AppBannerBloc>(
          create: (context) => AppBannerBloc(
            keyValueStore: localKeyValueStore,
            auth: context.read<ArDriveAuth>(),
          ),
          // Uncomment to enable announcement banner on app start:
          // ..add(const AppBannerRequested(banner: AppBannerType.announcement)),
        ),
        BlocProvider(
          create: (context) => PublicationsCubit(
            repository: context.read<PublicationRepository>(),
            profileCubit: context.read<ProfileCubit>(),
          ),
        ),
        // Publications and deployments together, for the Web pages nav
        // heading and page. Lazy: nothing reads it until the nav shows.
        BlocProvider(
          create: (context) => WebPagesCubit(
            driveDao: context.read<DriveDao>(),
            publicationsCubit: context.read<PublicationsCubit>(),
            profileCubit: context.read<ProfileCubit>(),
          ),
        ),
        // Lazy, and inert while names are off.
        BlocProvider(
          create: (context) => ArNSWalletCubit(
            arioSDK: ArioSDKFactory().create(),
            store: context.read<ArNSWalletStore>(),
            auth: context.read<ArDriveAuth>(),
            isEnabled: () =>
                configService.config.enableArNS && !PublicationMode.isOn,
          ),
        ),
        // The linked ArNS wallet's names, for rows, the details panel, the
        // name dialog and the Names page. Lazy: only read while names are on.
        BlocProvider(
          create: (context) => ArNSNamesCubit(
            repository: context.read<ArNSNamesRepository>(),
            walletCubit: context.read<ArNSWalletCubit>(),
          ),
        ),
        BlocProvider(
          create: (context) => ProfileNameBloc(
            context.read<ProfileLogoRepository>(),
            context.read<ArDriveAuth>(),
          ),
        ),
      ];

  List<SingleChildWidget> get repositoryProviders => [
        // Navigation, offered to the widgets that have somewhere to go.
        //
        // `.value`, and the delegate is owned by this State: it is handed to
        // `MaterialApp.router` below and must outlive every rebuild of this
        // subtree, so nothing here may create or dispose it.
        //
        // `ListenableProvider` rather than `RepositoryProvider`, because the
        // delegate is a [ChangeNotifier] and provider rejects one of those
        // behind a plain `Provider` - a dependent would never be told it had
        // changed. Nothing here watches it; the router does that.
        //
        // Provided rather than reached for through `Router.of`, so that a
        // widget that navigates can be mounted, tapped and checked against a
        // real delegate in a test without standing up the whole app.
        ListenableProvider<AppRouterDelegate>.value(value: _routerDelegate),
        RepositoryProvider<ArweaveService>(create: (_) => arweave),
        RepositoryProvider<DriveUnlocker>.value(value: driveUnlocker),
        RepositoryProvider<DriveUnlockSession>.value(
          value: driveUnlocker.session,
        ),
        // repository provider for UploadFileChecker
        RepositoryProvider<UploadFileSizeChecker>(
          create: (_) => UploadFileSizeChecker(
            fileSizeWarning: fileSizeWarning,
            fileSizeLimit: fileSizeLimit,
          ),
        ),
        RepositoryProvider<ArweaveService>(create: (_) => arweave),
        Provider<ConfigService>(
          create: (_) => configService,
        ),
        RepositoryProvider<TurboUploadService>(
          create: (_) => _turboUpload,
        ),
        RepositoryProvider<PaymentService>(
          create: (_) => _turboPayment,
        ),
        RepositoryProvider<PermanenceCache>.value(
          value: PermanenceCache.shared,
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
        RepositoryProvider<Database>(create: (_) => db),
        RepositoryProvider<ProfileDao>(
            create: (context) => context.read<Database>().profileDao),
        RepositoryProvider<DriveDao>(
            create: (context) => context.read<Database>().driveDao),
        RepositoryProvider(create: (_) => ArNSWalletStore()),
        RepositoryProvider(create: (_) => ArNSPendingActionStore()),
        RepositoryProvider<UserRepository>(
          create: (context) => UserRepository(
            context.read<ProfileDao>(),
            context.read<ArweaveService>(),
            ArioSDKFactory().create(),
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
            arweave: arweave,
            userRepository: context.read<UserRepository>(),
            arnsWalletStore: context.read<ArNSWalletStore>(),
            arnsPendingActionStore: context.read<ArNSPendingActionStore>(),
            driveUnlocker: driveUnlocker,
          ),
        ),
        RepositoryProvider(
          create: (_) => UserPreferencesRepository(
            themeDetector: ThemeDetector(),
            auth: _.read<ArDriveAuth>(),
          ),
        ),
        RepositoryProvider(
          create: (_) => LicenseService(),
        ),
        RepositoryProvider(
          create: (_) => FolderRepository(
            _.read<DriveDao>(),
          ),
        ),
        RepositoryProvider(
          create: (_) => FileRepository(
            _.read<DriveDao>(),
            _.read<FolderRepository>(),
          ),
        ),
        RepositoryProvider(
          create: (_) => SyncRepository(
            arweave: arweave,
            configService: configService,
            driveDao: _.read<DriveDao>(),
            batchProcessor: BatchProcessor(),
            snapshotValidationService: SnapshotValidationService(
              configService: configService,
            ),
            userPreferencesRepository: _.read<UserPreferencesRepository>(),
            driveUnlocker: driveUnlocker,
          ),
        ),
        RepositoryProvider(
          create: (_) => ArDriveDownloader(
            ardriveIo: ArDriveIO(),
            arweave: arweave,
            ioFileAdapter: IOFileAdapter(),
          ),
        ),
        SingleChildBuilder(
          builder: (context, child) {
            final arweaveService = context.read<ArweaveService>();
            return RepositoryProvider<ArDriveUploader>.value(
              value: ArDriveUploader(
                turboUploadUri:
                    Uri.parse(configService.config.defaultTurboUploadUrl!),
                getArweaveForD2n: () => arweaveService.client,
                metadataGenerator: ARFSUploadMetadataGenerator(
                  tagsGenerator: ARFSTagsGenerator(
                    appInfoServices: AppInfoServices(),
                  ),
                ),
                pstService: context.read<PstService>(),
              ),
              child: RepositoryProvider(
                create: (context) => ThumbnailRepository(
                  arDriveDownloader: ArDriveDownloader(
                    arweave: context.read<ArweaveService>(),
                    ardriveIo: ArDriveIO(),
                    ioFileAdapter: IOFileAdapter(),
                  ),
                  driveDao: context.read<DriveDao>(),
                  arweaveService: context.read<ArweaveService>(),
                  arDriveAuth: context.read<ArDriveAuth>(),
                  arDriveUploader: context.read<ArDriveUploader>(),
                  turboUploadService: context.read<TurboUploadService>(),
                ),
                child: RepositoryProvider(
                  create: (context) =>
                      createArDriveUploadPreparationManager(context),
                  child: RepositoryProvider(
                    create: (context) => createUploadRepository(context),
                    child: child,
                  ),
                ),
              ),
            );
          },
        ),
        RepositoryProvider(
          create: (context) => ProfileLogoRepository(
            localKeyValueStore,
          ),
        ),
        // One for the app, so what a publish adds is known everywhere at once.
        // Publications read through their own gateway, whatever the data
        // gateway setting is.
        RepositoryProvider(
          create: (context) => PublicationRepository(
            graphQLRetry: arweave.graphQLRetry,
            gatewayUrl: () => configService.config.publicationGatewayUrl,
          ),
        ),
        // Names (docs/NAMES.md). Built on first read, which nothing does
        // while `enableArNS` is off.
        RepositoryProvider(
          create: (_) => TurboArNSActionClient(
            paymentUrl: () => configService.config.defaultTurboPaymentUrl!,
          ),
        ),
        RepositoryProvider(
          create: (context) => ArNSNamesRepository(
            arioSDK: ArioSDKFactory().create(),
            dao: context.read<Database>().aRNSDao,
            publications: OwnerPublicationLookup(
              repository: context.read<PublicationRepository>(),
              ownerAddress: () {
                final auth = context.read<ArDriveAuth>();
                try {
                  return auth.currentUser.walletAddress;
                } catch (_) {
                  return null;
                }
              },
            ),
          ),
        ),
      ];
}
