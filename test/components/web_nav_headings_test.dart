import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/arns/presentation/names/arns_names_cubit.dart';
import 'package:ardrive/components/nav_sections.dart';
import 'package:ardrive/components/web_nav_headings.dart';
import 'package:ardrive/drives_list/domain/drive_scope.dart';
import 'package:ardrive/drives_list/presentation/drive_scope_rail.dart';
import 'package:ardrive/pages/app_route_information_parser.dart';
import 'package:ardrive/pages/app_route_path.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/web_pages/domain/web_page.dart';
import 'package:ardrive/web_pages/presentation/web_pages_cubit.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _MockConfigService extends Mock implements ConfigService {}

class _MockNamesCubit extends MockCubit<ArNSNamesState>
    implements ArNSNamesCubit {}

class _MockWebPagesCubit extends MockCubit<WebPagesState>
    implements WebPagesCubit {}

ArNSManagedName _name(String name, {Duration? leaseLeft}) => ArNSManagedName(
      name: name,
      processId: 'ant-$name',
      role: ArNSRole.owner,
      type: leaseLeft == null ? ArNSNameType.permabuy : ArNSNameType.lease,
      endTimestamp: leaseLeft == null ? null : DateTime.now().add(leaseLeft),
      undernameLimit: 10,
      records: const [],
    );

WebPage _page(int i) => WebPage(
      kind: WebPageKind.deployment,
      id: 'page-$i',
      title: 'Page $i',
      driveId: 'd',
      driveName: 'Site',
      folderName: null,
      openFolderId: 'd-root',
      dataTxId: 'tx-$i',
      updatedAt: DateTime(2026, 1, i),
    );

void main() {
  late _MockConfigService config;
  late AppRouterDelegate delegate;
  late _MockNamesCubit names;
  late _MockWebPagesCubit webPages;

  setUp(() {
    config = _MockConfigService();
    delegate = AppRouterDelegate();
    names = _MockNamesCubit();
    webPages = _MockWebPagesCubit();
    whenListen(names, const Stream<ArNSNamesState>.empty(),
        initialState: const ArNSNamesState());
    whenListen(webPages, const Stream<WebPagesState>.empty(),
        initialState: const WebPagesState(loaded: true));
  });

  void namesAre(List<ArNSManagedName> list) => whenListen(
        names,
        const Stream<ArNSNamesState>.empty(),
        initialState: ArNSNamesState(
          status: ArNSNamesStatus.loaded,
          address: 'sol',
          names: list,
        ),
      );

  void pagesAre(List<WebPage> list) => whenListen(
        webPages,
        const Stream<WebPagesState>.empty(),
        initialState: WebPagesState(loaded: true, pages: list),
      );

  Future<void> pump(
    WidgetTester tester, {
    bool arns = true,
    bool publishing = true,
    bool showLabel = true,
    NavSectionsCubit? sections,
  }) async {
    when(() => config.config).thenReturn(AppConfig(
      stripePublishableKey: '',
      allowedDataItemSizeForTurbo: 100,
      enableArNS: arns,
      enableDriveStatePublishing: publishing,
    ));
    await tester.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
              BlocProvider<ArNSNamesCubit>.value(value: names),
              BlocProvider<WebPagesCubit>.value(value: webPages),
              if (sections != null)
                BlocProvider<NavSectionsCubit>.value(value: sections),
            ],
            child: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: showLabel ? 240 : 64,
                  child: WebNavHeadings(showLabel: showLabel),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('Names', () {
    testWidgets('lists the names bare, without .ar.io', (tester) async {
      namesAre([_name('maya'), _name('studio')]);
      await pump(tester);

      expect(find.text('Names'), findsOneWidget);
      expect(find.text('maya'), findsOneWidget);
      expect(find.text('studio'), findsOneWidget);
      expect(find.textContaining('.ar.io'), findsNothing);
    });

    testWidgets('its words open the Names page', (tester) async {
      namesAre([_name('maya')]);
      await pump(tester);

      await tester.tap(find.text('Names'));
      await tester.pump();

      expect(delegate.showingNames, isTrue);
      expect(delegate.shownName, isNull);
      expect(delegate.currentConfiguration.names, isTrue);
      expect(find.text('maya'), findsOneWidget, reason: 'it did not fold');
    });

    testWidgets('its chevron alone folds the names away', (tester) async {
      namesAre([_name('maya')]);
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('nav-toggle-Names')));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('maya'), findsNothing);
      expect(delegate.showingNames, isFalse, reason: 'it did not navigate');

      await tester.tap(find.byKey(const ValueKey('nav-toggle-Names')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('maya'), findsOneWidget);
    });

    testWidgets('a screen reader hears two buttons: the page and the fold',
        (tester) async {
      final semantics = tester.ensureSemantics();
      namesAre([_name('maya')]);
      await pump(tester);

      expect(
        tester.getSemantics(find.byKey(const ValueKey('nav-toggle-Names'))),
        containsSemantics(
          label: 'Hide Names',
          isButton: true,
          hasExpandedState: true,
          isExpanded: true,
        ),
      );
      final heading = tester.widget<DriveNavRow>(find.ancestor(
        of: find.text('Names'),
        matching: find.byType(DriveNavRow),
      ));
      expect(heading.isExpanded, isTrue);
      semantics.dispose();
    });

    testWidgets("a name opens that name's page", (tester) async {
      namesAre([_name('maya'), _name('studio')]);
      await pump(tester);

      await tester.tap(find.text('studio'));
      await tester.pump();

      expect(delegate.showingNames, isTrue);
      expect(delegate.shownName, 'studio');
      expect(delegate.currentConfiguration.arnsName, 'studio');
    });

    testWidgets('a red dot on a lease that ends within 30 days',
        (tester) async {
      namesAre([
        _name('soon', leaseLeft: const Duration(days: 12)),
        _name('later', leaseLeft: const Duration(days: 90)),
        _name('forever'),
      ]);
      await pump(tester);

      final dot = find.byKey(const ValueKey('arns-renewal-dot'));
      expect(dot, findsOneWidget);
      final row = tester.widget<DriveNavRow>(
        find.ancestor(of: dot, matching: find.byType(DriveNavRow)),
      );
      expect(row.label, 'soon');
    });

    testWidgets('the first 8, then Show all', (tester) async {
      namesAre([for (var i = 0; i < 10; i++) _name('name$i')]);
      await pump(tester);

      expect(find.text('name7'), findsOneWidget);
      expect(find.text('name8'), findsNothing);
      expect(find.text('Show all 10'), findsOneWidget);

      await tester.tap(find.text('Show all 10'));
      await tester.pump();
      expect(delegate.showingNames, isTrue);
      expect(delegate.shownName, isNull);
    });

    testWidgets('no names: the heading alone, with no chevron', (tester) async {
      await pump(tester);

      expect(find.text('Names'), findsOneWidget);
      expect(find.byKey(const ValueKey('nav-toggle-Names')), findsNothing);
    });
  });

  group('Web pages', () {
    testWidgets('its words open the Web pages page', (tester) async {
      pagesAre([_page(1)]);
      await pump(tester);

      expect(find.text('Page 1'), findsOneWidget);
      await tester.tap(find.text('Web pages'));
      await tester.pump();

      expect(delegate.showingWebPages, isTrue);
      expect(delegate.currentConfiguration.webPages, isTrue);
    });

    testWidgets('its chevron alone folds the pages away', (tester) async {
      pagesAre([_page(1)]);
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('nav-toggle-Web pages')));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Page 1'), findsNothing);
      expect(delegate.showingWebPages, isFalse);
    });

    testWidgets('the first 8, then Show all', (tester) async {
      pagesAre([for (var i = 1; i <= 12; i++) _page(i)]);
      await pump(tester);

      expect(find.text('Page 8'), findsOneWidget);
      expect(find.text('Page 9'), findsNothing);
      await tester.tap(find.text('Show all 12'));
      await tester.pump();
      expect(delegate.showingWebPages, isTrue);
    });

    testWidgets('only while publishing is on', (tester) async {
      await pump(tester, publishing: false);

      expect(find.text('Web pages'), findsNothing);
      expect(find.text('Names'), findsOneWidget);
    });
  });

  // Phil: opening Web pages leaves only Web pages open in the nav.
  testWidgets('opening a page folds every other heading and opens its own',
      (tester) async {
    namesAre([_name('maya')]);
    pagesAre([_page(1)]);
    final sections = NavSectionsCubit()..toggle(NavSection.webPages);
    addTearDown(sections.close);
    await pump(tester, sections: sections);
    expect(find.text('Page 1'), findsNothing);
    expect(find.text('maya'), findsOneWidget);

    await tester.tap(find.text('Web pages'));
    await tester.pump();

    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('maya'), findsNothing);
    expect(sections.state, {...NavSection.values}..remove(NavSection.webPages));
    expect(delegate.showingWebPages, isTrue);

    await tester.tap(find.text('Names'));
    await tester.pump();

    expect(find.text('maya'), findsOneWidget);
    expect(find.text('Page 1'), findsNothing);
  });

  testWidgets('the collapsed rail: one icon each, to their pages',
      (tester) async {
    namesAre([_name('maya')]);
    pagesAre([_page(1)]);
    await pump(tester, showLabel: false);

    expect(find.text('maya'), findsNothing);
    expect(find.text('Page 1'), findsNothing);
    await tester.tap(find.byIcon(WebPagesNavHeading.icon));
    await tester.pump();
    expect(delegate.showingWebPages, isTrue);
    await tester.tap(find.byIcon(NamesNavHeading.icon));
    await tester.pump();
    expect(delegate.showingNames, isTrue);
    expect(delegate.showingWebPages, isFalse);
  });

  testWidgets('nothing is drawn while both are off', (tester) async {
    await pump(tester, arns: false, publishing: false);

    expect(find.text('Names'), findsNothing);
    expect(find.text('Web pages'), findsNothing);
    expect(tester.getSize(find.byType(WebNavHeadings)).height, 0);
  });

  group('routes', () {
    final parser = AppRouteInformationParser();

    test('/names parses to the Names page', () async {
      final path = await parser.parseRouteInformation(
        RouteInformation(uri: Uri.parse('/names')),
      );
      expect(path.names, isTrue);
      expect(path.arnsName, isNull);
      expect(path.driveId, isNull);
    });

    test("/names/<name> parses to that name's page and back", () async {
      final path = await parser.parseRouteInformation(
        RouteInformation(uri: Uri.parse('/names/studio')),
      );
      expect(path.names, isTrue);
      expect(path.arnsName, 'studio');
      expect(
        parser.restoreRouteInformation(path).uri.toString(),
        '/names/studio',
      );
    });

    test('/names/<name> is read in lowercase, as ArNS names are', () async {
      final path = await parser.parseRouteInformation(
        RouteInformation(uri: Uri.parse('/names/Studio')),
      );
      expect(path.arnsName, 'studio');
    });

    test('/web-pages parses, and is written back over a selected drive',
        () async {
      final path = await parser.parseRouteInformation(
        RouteInformation(uri: Uri.parse('/web-pages')),
      );
      expect(path.webPages, isTrue);
      const over = AppRoutePath(webPages: true, driveId: 'drive');
      expect(parser.restoreRouteInformation(over).uri.toString(), '/web-pages');
    });

    test('/names is written back over a selected drive', () {
      const path = AppRoutePath(names: true, driveId: 'drive');
      expect(parser.restoreRouteInformation(path).uri.toString(), '/names');
    });

    test('leaves drive links as they were', () async {
      final path = await parser.parseRouteInformation(
        RouteInformation(uri: Uri.parse('/drives/abc')),
      );
      expect(path.names, isFalse);
      expect(path.webPages, isFalse);
      expect(path.driveId, 'abc');
    });

    test('showing the drives list leaves either page', () {
      delegate.showNames(name: 'studio');
      delegate.showDrivesList();
      expect(delegate.showingNames, isFalse);
      expect(delegate.showingDrivesList, isTrue);

      delegate.showWebPages();
      expect(delegate.showingDrivesList, isFalse);
      delegate.showDrivesList(scope: DriveScope.public);
      expect(delegate.showingWebPages, isFalse);
      expect(delegate.drivesListScope, DriveScope.public);
    });

    test('the two pages replace each other', () {
      delegate.showWebPages();
      delegate.showNames();
      expect(delegate.showingWebPages, isFalse);
      delegate.showWebPages();
      expect(delegate.showingNames, isFalse);
    });

    test('opening a drive from the nav leaves the page', () {
      delegate.showWebPages();
      delegate.openDriveFromList('drive');

      expect(delegate.showingWebPages, isFalse);
      expect(delegate.driveId, 'drive');
    });
  });
}
