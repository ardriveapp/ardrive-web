import 'package:ardrive/components/list_page/list_table.dart';
import 'package:ardrive/drives_list/domain/drive_scope.dart';
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
import 'package:provider/provider.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _MockConfigService extends Mock implements ConfigService {}

class _MockWebPagesCubit extends MockCubit<WebPagesState>
    implements WebPagesCubit {}

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

  setUp(() {
    config = _MockConfigService();
    when(() => config.config).thenReturn(AppConfig(
      stripePublishableKey: '',
      allowedDataItemSizeForTurbo: 100,
      enableDriveStatePublishing: true,
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

  testWidgets('nothing yet: Publish and the empty state go to public drives',
      (tester) async {
    pagesAre(const []);
    await pump(tester);

    expect(find.text('Nothing published yet'), findsOneWidget);
    await tester.tap(find.text('Publish'));
    expect(delegate.showingDrivesList, isTrue);
    expect(delegate.drivesListScope, DriveScope.public);
  });
}
