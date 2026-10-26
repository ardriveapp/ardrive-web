import 'package:ardrive/components/side_bar.dart';
import 'package:ardrive/pages/app_route_information_parser.dart';
import 'package:ardrive/pages/app_route_path.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockConfigService extends Mock implements ConfigService {}

void main() {
  late _MockConfigService config;
  late AppRouterDelegate delegate;

  setUp(() {
    config = _MockConfigService();
    delegate = AppRouterDelegate();
  });

  Future<void> pump(WidgetTester tester, {required bool enabled}) async {
    when(() => config.config).thenReturn(AppConfig(
      stripePublishableKey: '',
      allowedDataItemSizeForTurbo: 100,
      enableArNS: enabled,
    ));
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MultiProvider(
            providers: [
              RepositoryProvider<ConfigService>.value(value: config),
              ChangeNotifierProvider<AppRouterDelegate>.value(
                value: delegate,
              ),
            ],
            child: const Scaffold(
              body: OnTheWebNavGroup(showLabel: true),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('On the web › Names shows while names are on', (tester) async {
    await pump(tester, enabled: true);

    expect(find.text('On the web'), findsOneWidget);
    expect(find.text('Names'), findsOneWidget);

    await tester.tap(find.text('Names'));
    await tester.pump();

    expect(delegate.showingNames, isTrue);
    expect(delegate.currentConfiguration.names, isTrue);
  });

  testWidgets('nothing is drawn while names are off', (tester) async {
    await pump(tester, enabled: false);

    expect(find.text('On the web'), findsNothing);
    expect(find.text('Names'), findsNothing);
    expect(
      tester.getSize(find.byType(OnTheWebNavGroup)),
      Size.zero,
    );
  });

  group('/names', () {
    final parser = AppRouteInformationParser();

    test('parses to the Names page', () async {
      final path = await parser.parseRouteInformation(
        RouteInformation(uri: Uri.parse('/names')),
      );
      expect(path.names, isTrue);
      expect(path.driveId, isNull);
    });

    test('is written back as /names, over a selected drive', () {
      const path = AppRoutePath(names: true, driveId: 'drive');
      expect(parser.restoreRouteInformation(path).uri.toString(), '/names');
    });

    test('leaves drive links as they were', () async {
      final path = await parser.parseRouteInformation(
        RouteInformation(uri: Uri.parse('/drives/abc')),
      );
      expect(path.names, isFalse);
      expect(path.driveId, 'abc');
    });

    test('showing the drives list leaves the Names page', () {
      delegate.showNames();
      delegate.showDrivesList();

      expect(delegate.showingNames, isFalse);
      expect(delegate.showingDrivesList, isTrue);
    });

    test('opening a drive from the nav leaves the Names page', () {
      delegate.showNames();
      delegate.openDriveFromList('drive');

      expect(delegate.showingNames, isFalse);
      expect(delegate.driveId, 'drive');
    });
  });
}
