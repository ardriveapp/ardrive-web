import 'package:ardrive/arns/presentation/names/arns_names_cubit.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/components/details_panel.dart';
import 'package:ardrive/drives_list/domain/drive_scope.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/publication/data/publication_repository.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/web_pages/domain/web_page.dart';
import 'package:ardrive/web_pages/presentation/web_pages_cubit.dart';
import 'package:ardrive/web_pages/presentation/web_pages_page.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/mocks.dart';
import 'package:drift/drift.dart' show Selectable;
import 'package:provider/provider.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _MockConfigService extends Mock implements ConfigService {}

class _MockWebPagesCubit extends MockCubit<WebPagesState>
    implements WebPagesCubit {}

class _MockNamesCubit extends MockCubit<ArNSNamesState>
    implements ArNSNamesCubit {}

class _MockDriveSelectable extends Mock implements Selectable<Drive> {}

class _RecordingUrlLauncher extends UrlLauncherPlatform {
  final List<String> launched = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    launched.add(url);
    return true;
  }
}

WebPage _page(String title, DateTime at, {bool deployment = true}) => WebPage(
      kind: deployment ? WebPageKind.deployment : WebPageKind.publication,
      publication: deployment ? null : const Publication([]),
      id: title,
      title: title,
      driveId: 'd',
      driveName: 'Websites',
      folderName: deployment ? 'Campaigns' : null,
      openFolderId: 'f',
      dataTxId: '$title-tx',
      updatedAt: at,
    );

/// Web pages in the list pages' frame: the shared table, a click shows a
/// page's details, a double-click opens the page.
void main() {
  late _MockConfigService config;
  late _MockWebPagesCubit cubit;
  late AppRouterDelegate delegate;
  late _RecordingUrlLauncher launcher;
  late MockDrivesCubit drives;
  late MockDriveDao driveDao;
  late _MockNamesCubit names;
  var arns = false;

  setUp(() {
    arns = false;
    drives = MockDrivesCubit();
    whenListen(drives, const Stream<DrivesState>.empty(),
        initialState: DrivesLoadInProgress());
    driveDao = MockDriveDao();
    final noDrive = _MockDriveSelectable();
    when(() => noDrive.getSingleOrNull()).thenAnswer((_) async => null);
    when(() => driveDao.driveById(driveId: any(named: 'driveId')))
        .thenReturn(noDrive);
    names = _MockNamesCubit();
    whenListen(names, const Stream<ArNSNamesState>.empty(),
        initialState: const ArNSNamesState());
    config = _MockConfigService();
    when(() => config.config).thenAnswer((_) => AppConfig(
          stripePublishableKey: '',
          allowedDataItemSizeForTurbo: 100,
          enableDriveStatePublishing: true,
          enableArNS: arns,
        ));
    cubit = _MockWebPagesCubit();
    delegate = AppRouterDelegate()..showingWebPages = true;
    launcher = _RecordingUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  void pagesAre(List<WebPage> pages) => whenListen(
        cubit,
        const Stream<WebPagesState>.empty(),
        initialState: WebPagesState(loaded: true, pages: pages),
      );

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ArDriveApp(
        themeData: lightTheme(),
        builder: (context) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MultiProvider(
            providers: [
              RepositoryProvider<ConfigService>.value(value: config),
              ChangeNotifierProvider<AppRouterDelegate>.value(
                value: delegate,
              ),
              BlocProvider<WebPagesCubit>.value(value: cubit),
              BlocProvider<DrivesCubit>.value(value: drives),
              BlocProvider<ArNSNamesCubit>.value(value: names),
              RepositoryProvider<DriveDao>.value(value: driveDao),
            ],
            child: const Scaffold(body: WebPagesBody()),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<TestGesture> mouse(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    return gesture;
  }

  Future<void> click(
      WidgetTester tester, TestGesture pointer, String text) async {
    await pointer.down(tester.getCenter(find.text(text).first));
    await pointer.up();
    await tester.pump();
  }

  final older = _page('Recipes', DateTime(2026, 1, 2));
  final newer = _page('Field notes', DateTime(2026, 10, 2), deployment: false);

  testWidgets('newest first, and sorts by name from its heading',
      (tester) async {
    pagesAre([older, newer]);
    await pump(tester);

    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('Field notes'), lessThan(top('Recipes')));

    await tester.tap(find.text('Page'));
    await tester.pump();
    expect(top('Field notes'), lessThan(top('Recipes')));
    await tester.tap(find.text('Page'));
    await tester.pump();
    expect(top('Recipes'), lessThan(top('Field notes')));
  });

  testWidgets('a click shows the page in a details panel', (tester) async {
    pagesAre([older, newer]);
    await pump(tester);
    final pointer = await mouse(tester);

    await click(tester, pointer, 'Recipes');
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.byType(WebPageDetailsPanel), findsOneWidget);
    expect(find.text('From'), findsOneWidget);
    expect(find.text('Campaigns folder, Websites drive'), findsWidgets);
    expect(launcher.launched, isEmpty, reason: 'a click only chooses');

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(WebPageDetailsPanel), findsNothing);
  });

  testWidgets('a double-click opens the page', (tester) async {
    pagesAre([older]);
    await pump(tester);
    final pointer = await mouse(tester);

    await click(tester, pointer, 'Recipes');
    await tester.pump(const Duration(milliseconds: 100));
    await click(tester, pointer, 'Recipes');
    await tester.pumpAndSettle();

    expect(launcher.launched, [
      '${AppConfig(stripePublishableKey: '', allowedDataItemSizeForTurbo: 100).arweaveGatewayForDataRequest.url}/Recipes-tx',
    ]);
  });

  testWidgets('no inline copy button in the rows', (tester) async {
    pagesAre([older]);
    await pump(tester);

    expect(find.byTooltip('Copy link'), findsNothing);
  });

  testWidgets('nothing yet: Publish and the empty state go to public drives',
      (tester) async {
    pagesAre(const []);
    await pump(tester);

    expect(find.text('Nothing published yet'), findsOneWidget);
    await tester.tap(find.text('Publish'));
    expect(delegate.showingDrivesList, isTrue);
    expect(delegate.drivesListScope, DriveScope.public);
  });

  /// The icon says it is a deployment; a tag beside the name said it again.
  testWidgets('a deployment is marked by its icon alone', (tester) async {
    final semantics = tester.ensureSemantics();
    pagesAre([older, newer]);
    await pump(tester);

    expect(find.text('Deployment'), findsNothing);
    expect(find.byType(ArDriveTag), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Deployment')), findsOneWidget,
        reason: 'Recipes is a deployment and Field notes is not');
    semantics.dispose();
  });

  Future<void> choose(WidgetTester tester, String title) async {
    final pointer = await mouse(tester);
    await click(tester, pointer, title);
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
  }

  /// The file details panel's shape: its actions are icon buttons in the
  /// toolbar above the name, not buttons under the details.
  Finder toolbarAction(String tooltip) => find.descendant(
        of: find.byType(DetailsPanelToolbarFrame),
        matching: find.ancestor(
          of: find.byTooltip(tooltip),
          matching: find.byType(ArDriveIconButton),
        ),
      );

  testWidgets("the panel's actions are icon buttons in its toolbar",
      (tester) async {
    arns = true;
    pagesAre([older, newer]);
    await pump(tester);

    await choose(tester, 'Field notes');
    for (final tooltip in [
      'Open page',
      'Update page',
      'Add name',
      'Open folder',
    ]) {
      expect(toolbarAction(tooltip), findsOneWidget, reason: tooltip);
    }
    // In the row menu's order, after the panel's own copy of the link.
    double left(String tooltip) => tester.getTopLeft(toolbarAction(tooltip)).dx;
    expect(left('Open page'), lessThan(left('Update page')));
    expect(left('Update page'), lessThan(left('Add name')));
    expect(left('Add name'), lessThan(left('Open folder')));
    expect(
      find.descendant(
        of: find.byType(WebPageDetailsPanel),
        matching: find.byType(ArDriveButtonNew),
      ),
      findsNothing,
      reason: 'no buttons left under the details',
    );
  });

  testWidgets('a deployment has nothing to update', (tester) async {
    pagesAre([older]);
    await pump(tester);

    await choose(tester, 'Recipes');

    expect(toolbarAction('Open page'), findsOneWidget);
    expect(toolbarAction('Open folder'), findsOneWidget);
    expect(find.byTooltip('Update page'), findsNothing);
    expect(find.byTooltip('Add name'), findsNothing, reason: 'names are off');
  });

  testWidgets('Open page opens the page', (tester) async {
    pagesAre([older]);
    await pump(tester);
    await choose(tester, 'Recipes');

    await tester.tap(toolbarAction('Open page'));
    await tester.pump();

    expect(launcher.launched, hasLength(1));
    expect(launcher.launched.single, endsWith('/Recipes-tx'));
  });

  testWidgets('Open folder shows the page in its drive', (tester) async {
    pagesAre([older]);
    await pump(tester);
    await choose(tester, 'Recipes');

    await tester.tap(toolbarAction('Open folder'));
    await tester.pump();

    verify(() => drives.selectDrive('d')).called(1);
  });

  testWidgets('Update page reads the drive to publish it again',
      (tester) async {
    pagesAre([newer]);
    await pump(tester);
    await choose(tester, 'Field notes');

    await tester.tap(toolbarAction('Update page'));
    await tester.pump();

    verify(() => driveDao.driveById(driveId: 'd')).called(1);
  });
}
