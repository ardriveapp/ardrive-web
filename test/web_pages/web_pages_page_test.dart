import 'package:ardrive/arns/presentation/names/arns_names_cubit.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/components/details_panel.dart';
import 'package:ardrive/components/drive_picker/drive_picker_dialog.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/components/list_page/list_table.dart';
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

class _MockActivityTracker extends Mock implements ActivityTracker {}

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
              // Dialogs pause it while they are up.
              ListenableProvider<ActivityTracker>.value(
                value: _MockActivityTracker(),
              ),
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

  testWidgets('no checkboxes: web pages have no bulk actions', (tester) async {
    // Checkboxes only where there is something to do with several rows at
    // once: the explorer and Your drives. Not on hover, not on a long press.
    pagesAre([older, newer]);
    await pump(tester);
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
    await pointer.moveTo(tester.getCenter(find.byType(ListTableRow).first));
    await tester.pumpAndSettle();
    await tester.longPress(find.byType(ListTableRow).first,
        warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byType(ListTableRow), findsWidgets);
    expect(find.byType(ArDriveCheckBox), findsNothing);
    expect(find.byType(ArDriveMultiSelectBox), findsNothing);
  });

  testWidgets('no inline copy button in the rows', (tester) async {
    pagesAre([older]);
    await pump(tester);

    expect(find.byTooltip('Copy link'), findsNothing);
  });

  testWidgets('nothing yet: the empty state goes to public drives',
      (tester) async {
    pagesAre(const []);
    await pump(tester);

    expect(find.text('Nothing published yet'), findsOneWidget);
    await tester.tap(find.text('Go to your drives'));
    expect(delegate.showingDrivesList, isTrue);
    expect(delegate.drivesListScope, DriveScope.public);
  });

  /// Publish used to go to Your drives and leave the rest to the reader. It
  /// asks what to publish, in the drive picker, then publishes it as its
  /// menu does.
  testWidgets('Publish asks what to publish, and says when nothing can be',
      (tester) async {
    pagesAre([older]);
    await pump(tester);

    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    expect(find.byType(DrivePickerDialog), findsOneWidget);
    expect(find.text('Publish to web'), findsOneWidget);
    // No public drive of the reader's can be published here.
    expect(find.text('No public drives yet'), findsOneWidget);
    expect(delegate.showingDrivesList, isFalse,
        reason: 'it no longer leaves the page');
  });

  group('icons, as the explorer draws them', () {
    IconData? iconOf(WidgetTester tester, String title) {
      final row = find.ancestor(
        of: find.text(title),
        matching: find.byType(ListTableRow),
      );
      return tester
          .widget<ArDriveIcon>(
            find.descendant(of: row, matching: find.byType(ArDriveIcon)).first,
          )
          .icon;
    }

    WebPage filePage(String name, {String? contentType}) => WebPage(
          kind: WebPageKind.filePage,
          publication: const Publication([]),
          id: name,
          title: name,
          driveId: 'd',
          driveName: 'Websites',
          folderName: null,
          openFolderId: 'f',
          dataTxId: '$name-tx',
          updatedAt: DateTime(2026, 3),
          contentType: contentType,
        );

    testWidgets("a file page has its file's type icon", (tester) async {
      pagesAre([
        filePage('permaman_detailed.png', contentType: 'image/png'),
        filePage('theme.mp3', contentType: 'audio/mpeg'),
      ]);
      await pump(tester);

      expect(
          iconOf(tester, 'permaman_detailed.png'), ArDriveIcons.image().icon);
      expect(iconOf(tester, 'theme.mp3'), ArDriveIcons.music().icon);
    });

    testWidgets("a drive's page has the drive icon, a folder's the folder's",
        (tester) async {
      final drivePage = _page('Websites', DateTime(2026, 2), deployment: false);
      final folderPage = WebPage(
        kind: WebPageKind.publication,
        publication: const Publication([]),
        id: 'campaigns',
        title: 'Campaigns',
        driveId: 'd',
        driveName: 'Websites',
        folderName: 'Campaigns',
        openFolderId: 'f',
        dataTxId: 'campaigns-tx',
        updatedAt: DateTime(2026, 3),
      );
      pagesAre([drivePage, folderPage]);
      await pump(tester);

      expect(iconOf(tester, 'Websites'), ArDriveIcons.publicDrive().icon);
      expect(iconOf(tester, 'Campaigns'), ArDriveIcons.folderOutline().icon);
    });
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

  /// The explorer's arrangement: the panel stands 16 off the list and runs
  /// to the window's edge. On the list pages it sat flush against the list.
  testWidgets('the panel stands apart from the list, as the explorer\'s does',
      (tester) async {
    pagesAre([older]);
    await pump(tester);
    final listBefore = tester.getRect(find.byType(CustomScrollView));
    expect(listBefore.right, 1400 - 16, reason: 'the page margin, no panel');

    await choose(tester, 'Recipes');

    final list = tester.getRect(find.byType(CustomScrollView));
    final panel = tester.getRect(find.byType(WebPageDetailsPanel));
    expect(panel.left - list.right, 16);
    expect(panel.right, 1400);
    expect(panel.width, 375, reason: "the explorer's width at 1400");
  });

  /// One label and value grid: a value that wraps stays on the right, as
  /// the dates do, rather than starting at the left of its half.
  testWidgets("the panel's links wrap on the right, like its other values",
      (tester) async {
    pagesAre([older]);
    await pump(tester);
    await choose(tester, 'Recipes');

    final links = tester.widgetList<ArDriveLink>(find.descendant(
      of: find.byType(WebPageDetailsPanel),
      matching: find.byType(ArDriveLink),
    ));
    expect(links, hasLength(2), reason: 'the link and where it comes from');
    for (final link in links) {
      expect(link.textAlign, TextAlign.right, reason: link.text);
    }
  });
}
