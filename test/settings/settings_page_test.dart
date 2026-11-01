import 'dart:async';

import 'package:ardrive/account/presentation/account_page.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/graphql_endpoint_dialog.dart';
import 'package:ardrive/components/list_page/list_page_layout.dart';
import 'package:ardrive/pages/app_route_information_parser.dart';
import 'package:ardrive/pages/app_route_path.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/services/config/selected_gateway.dart';
import 'package:ardrive/settings/presentation/settings_page.dart';
import 'package:ardrive/theme/theme_switcher_bloc.dart';
import 'package:ardrive/theme/theme_switcher_state.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/utils.dart';

class _MockPreferences extends Mock implements UserPreferencesRepository {}

class _MockArweave extends Mock implements ArweaveService {}

class _MockThemeBloc extends MockBloc<ThemeSwitcherEvent, ThemeSwitcherState>
    implements ThemeSwitcherBloc {}

class _FakeAppConfig extends Fake implements AppConfig {}

AppConfig _config({
  String gateway = 'https://turbo-gateway.com',
  String? graphQL,
  String upload = 'https://upload.ardrive.io',
  String payment = 'https://payment.ardrive.io',
  bool autoSync = false,
  bool snapshots = true,
  bool thumbnails = true,
  int interval = 300,
}) =>
    AppConfig(
      allowedDataItemSizeForTurbo: 0,
      stripePublishableKey: '',
      arweaveGatewayUrl: graphQL,
      arweaveGatewayForDataRequest: SelectedGateway(label: 'g', url: gateway),
      defaultTurboUploadUrl: upload,
      defaultTurboPaymentUrl: payment,
      autoSync: autoSync,
      enableSyncFromSnapshot: snapshots,
      uploadThumbnails: thumbnails,
      autoSyncIntervalInSeconds: interval,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeAppConfig());
    registerFallbackValue(ChangeTheme());
  });

  group('page', () {
    late MockConfigService configService;
    late _MockPreferences preferences;
    late _MockArweave arweave;
    late _MockThemeBloc theme;
    late AppConfig current;
    late AppConfig defaults;
    late bool syncOnSignIn;

    setUp(() {
      // Shipped configs carry a GraphQL server.
      current = _config(graphQL: 'https://turbo-gateway.com');
      defaults = _config(graphQL: 'https://turbo-gateway.com');
      syncOnSignIn = false;
      configService = MockConfigService();
      preferences = _MockPreferences();
      arweave = _MockArweave();
      theme = _MockThemeBloc();

      when(() => configService.config).thenAnswer((_) => current);
      when(() => configService.loadDefaultConfig())
          .thenAnswer((_) async => defaults);
      when(() => configService.updateAppConfig(any())).thenAnswer((i) async {
        current = i.positionalArguments.first as AppConfig;
      });
      when(() => preferences.watch()).thenAnswer((_) => const Stream.empty());
      when(() => preferences.currentPreferences).thenAnswer(
        (_) => UserPreferences(
          currentTheme: ArDriveThemes.light,
          lastSelectedDriveId: null,
          syncAllDrivesOnLogin: syncOnSignIn,
        ),
      );
      when(() => preferences.saveSyncAllDrivesOnLogin(any()))
          .thenAnswer((i) async {
        syncOnSignIn = i.positionalArguments.first as bool;
      });
      when(() => arweave.updateGraphQLEndpoint(any())).thenReturn(null);
      whenListen(
        theme,
        const Stream<ThemeSwitcherState>.empty(),
        initialState: ThemeSwitcherLightTheme(),
      );
    });

    Future<void> pump(
      WidgetTester tester, {
      Size size = const Size(1400, 2400),
      Widget? page,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider<ConfigService>.value(value: configService),
            RepositoryProvider<UserPreferencesRepository>.value(
              value: preferences,
            ),
            RepositoryProvider<ArweaveService>.value(value: arweave),
          ],
          child: BlocProvider<ThemeSwitcherBloc>.value(
            value: theme,
            child: ArDriveApp(
              themeData: lightTheme(),
              builder: (context) => MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: const [Locale('en', '')],
                theme: ArDriveTheme.of(context).themeData.materialThemeData,
                home: Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: page ?? const SettingsSections(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('every setting is there with its one-line explanation',
        (tester) async {
      await pump(tester);

      for (final text in [
        'Appearance',
        'Theme',
        'Light or dark.',
        'Sync',
        'Automatic sync',
        'Checks your drives for changes every 5 minutes while ArDrive is open.',
        'Sync all drives when I sign in',
        'Off: only the drive you open is read.',
        'Sync from snapshots',
        'Loads large drives faster from a saved copy. Turn off to read every change from the start.',
        'Uploads',
        'Upload with thumbnails',
        "Makes small previews of images. A public file's thumbnail is public too.",
        'Network',
        'Gateway',
        'Where ArDrive reads files from.',
        'GraphQL server',
        'Where ArDrive looks up your drives and files.',
        'Turbo services',
        'Where uploads and payments are sent.',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }

      // The explanation is in textMid.
      final colors = ArDriveTheme.of(tester.element(find.text('Theme')))
          .themeData
          .colorTokens;
      expect(
        tester
            .widget<Text>(find.text('Where ArDrive reads files from.'))
            .style!
            .color,
        colors.textMid,
      );
    });

    testWidgets('the sync interval is said as it is', (tester) async {
      current = _config(interval: 60);
      await pump(tester);
      expect(
        find.text(
            'Checks your drives for changes every minute while ArDrive is open.'),
        findsOneWidget,
      );
    });

    testWidgets('theme offers Light and Dark and switches', (tester) async {
      await pump(tester);

      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('Match my device'), findsNothing);

      // Already light: tapping it does nothing.
      await tester.tap(find.text('Light'));
      verifyNever(() => theme.add(any()));

      await tester.tap(find.text('Dark'));
      verify(() => theme.add(any(that: isA<ChangeTheme>()))).called(1);
    });

    testWidgets('the switches write to the config and the preferences',
        (tester) async {
      await pump(tester);

      await tester.tap(find.text('Automatic sync'));
      await tester.pumpAndSettle();
      expect(current.autoSync, isTrue);

      await tester.tap(find.text('Sync from snapshots'));
      await tester.pumpAndSettle();
      expect(current.enableSyncFromSnapshot, isFalse);

      await tester.tap(find.text('Upload with thumbnails'));
      await tester.pumpAndSettle();
      expect(current.uploadThumbnails, isFalse);

      await tester.tap(find.text('Sync all drives when I sign in'));
      await tester.pumpAndSettle();
      expect(syncOnSignIn, isTrue);
    });

    testWidgets('the network rows show their addresses', (tester) async {
      current = _config(graphQL: 'https://graphql.example');
      await pump(tester);

      expect(find.text('https://turbo-gateway.com'), findsOneWidget);
      expect(find.text('https://graphql.example'), findsOneWidget);
      expect(find.text('https://upload.ardrive.io'), findsOneWidget);
      expect(find.text('https://payment.ardrive.io'), findsOneWidget);
      expect(find.text('Change'), findsNWidgets(3));

      // Monospace, like every address.
      final style =
          tester.widget<Text>(find.text('https://graphql.example')).style!;
      expect(
          style.fontFamily,
          ArDriveTypographyNew.of(
            tester.element(find.text('Theme')),
          ).code().fontFamily);
    });

    testWidgets('an unset GraphQL server shows the one in use', (tester) async {
      current = _config();
      await pump(tester);
      expect(find.text('https://arweave.net'), findsOneWidget);
    });

    testWidgets('Reset is not offered where the value is the shipped one',
        (tester) async {
      await pump(tester);
      expect(find.text('Reset to default'), findsNothing);
    });

    testWidgets('Reset is offered where the value differs', (tester) async {
      current = _config(
        gateway: 'https://my.gateway',
        graphQL: 'https://graphql.example',
        upload: 'https://upload.example',
      );
      await pump(tester);
      expect(find.text('Reset to default'), findsNWidgets(3));
    });

    testWidgets('Reset puts the shipped GraphQL server back', (tester) async {
      current = _config(graphQL: 'https://graphql.example');
      await pump(tester);

      await tester.tap(find.byKey(const Key('settingsGraphQLServerReset')));
      await tester.pumpAndSettle();

      expect(current.arweaveGatewayUrl, 'https://turbo-gateway.com');
      verify(() => arweave.updateGraphQLEndpoint('https://turbo-gateway.com'))
          .called(1);
      expect(find.byKey(const Key('settingsGraphQLServerReset')), findsNothing);
    });

    testWidgets('no known defaults, no Reset', (tester) async {
      when(() => configService.loadDefaultConfig())
          .thenAnswer((_) async => throw StateError('no asset'));
      current = _config(gateway: 'https://my.gateway');
      await pump(tester);
      expect(find.text('Reset to default'), findsNothing);
    });

    testWidgets('Change opens the dialog', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('settingsGraphQLServerChange')));
      await tester.pumpAndSettle();
      expect(find.byType(GraphQLEndpointDialog), findsOneWidget);
    });

    testWidgets('content stops at 880 px, left-aligned, on a wide window',
        (tester) async {
      await pump(
        tester,
        page: const Align(
          alignment: Alignment.topLeft,
          child: PageContentColumn(child: SettingsSections()),
        ),
      );
      final section = find.byType(PageSection).first;
      expect(tester.getSize(section).width, pageContentMaxWidth);
      expect(pageContentMaxWidth, 880);
      expect(tester.getTopLeft(section).dx, 16);
    });

    testWidgets('no overflow at 390 px', (tester) async {
      current = _config(
        gateway: 'https://a-very-long-gateway-address.example.com/with/a/path',
        graphQL: 'https://a-very-long-graphql-address.example.com/path',
      );
      await pump(tester, size: const Size(390, 2400));
      expect(tester.takeException(), isNull);
    });
  });

  group('route', () {
    test('/settings parses to the page and back', () async {
      final parser = AppRouteInformationParser();
      final path = await parser.parseRouteInformation(
        RouteInformation(uri: Uri.parse('/settings')),
      );
      expect(path.settings, isTrue);
      expect(
        parser.restoreRouteInformation(AppRoutePath.settings()).uri.path,
        '/settings',
      );
    });

    test('a longer path is not the page', () async {
      final path = await AppRouteInformationParser().parseRouteInformation(
        RouteInformation(uri: Uri.parse('/settings/x')),
      );
      expect(path.settings, isFalse);
    });

    test('back returns to what the page covered', () {
      final router = AppRouterDelegate()..showNames();
      router.showSettings();
      expect(router.showingSettings, isTrue);
      expect(router.showingNames, isFalse);
      expect(router.currentConfiguration.settings, isTrue);

      router.closeSettings();
      expect(router.showingSettings, isFalse);
      expect(router.showingNames, isTrue);
    });

    test('Account, Billing and Settings replace each other and keep the origin',
        () {
      final router = AppRouterDelegate()..showNames();
      router
        ..showAccount()
        ..showSettings();
      expect(router.showingAccount, isFalse);
      expect(router.showingSettings, isTrue);

      router.showBilling();
      expect(router.showingSettings, isFalse);
      expect(router.showingBilling, isTrue);

      router.showSettings();
      expect(router.showingBilling, isFalse);
      router.closeSettings();
      expect(router.showingNames, isTrue);

      router
        ..showSettings()
        ..showAccount();
      expect(router.showingSettings, isFalse);
      router.closeAccount();
      expect(router.showingNames, isTrue);
    });

    test('back from an opened address lands on the drives list', () async {
      final router = AppRouterDelegate();
      await router.setNewRoutePath(AppRoutePath.settings());
      expect(router.showingSettings, isTrue);
      router.closeSettings();
      expect(router.showingSettings, isFalse);
      expect(router.showingDrivesList, isTrue);
    });

    test('is shown only to somebody signed in', () {
      final router = AppRouterDelegate()..showSettings();
      expect(
        router.showsSettings(
          ProfileLoggedIn(user: getTestUser(), useTurbo: false),
        ),
        isTrue,
      );
      for (final state in [
        ProfilePromptAdd(),
        ProfilePromptLogIn(),
        ProfileCheckingAvailability(),
      ]) {
        expect(router.showsSettings(state), isFalse, reason: '$state');
      }
    });

    test('a link to it is honoured after sign-in', () async {
      final router = AppRouterDelegate();
      await router.setNewRoutePath(AppRoutePath.settings());
      router.signingIn = true;
      router.landAfterSignIn();
      expect(router.showingSettings, isTrue);
      expect(router.showingDrivesList, isFalse);
    });

    test('opening a drive or another page leaves it', () {
      final router = AppRouterDelegate()..showSettings();
      router.openDriveFromList('d1');
      expect(router.showingSettings, isFalse);

      router
        ..showSettings()
        ..showWebPages();
      expect(router.showingSettings, isFalse);
    });
  });
}
