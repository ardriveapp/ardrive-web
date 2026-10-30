import 'package:ardrive/arns/data/arns_wallet_store.dart';
import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/arns/presentation/names/arns_names_cubit.dart';
import 'package:ardrive/arns/presentation/names_page/names_page.dart';
import 'package:ardrive/components/copy_button.dart';
import 'package:ardrive/components/details_panel.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _MockConfigService extends Mock implements ConfigService {}

class _MockNamesCubit extends MockCubit<ArNSNamesState>
    implements ArNSNamesCubit {}

class _MockWalletCubit extends MockCubit<ArNSWalletState>
    implements ArNSWalletCubit {}

ArNSManagedName _name(
  String name, {
  Duration? leaseLeft,
  ArNSRole role = ArNSRole.owner,
}) =>
    ArNSManagedName(
      name: name,
      processId: 'ant-$name',
      role: role,
      type: leaseLeft == null ? ArNSNameType.permabuy : ArNSNameType.lease,
      endTimestamp: leaseLeft == null ? null : DateTime.now().add(leaseLeft),
      undernameLimit: 10,
      records: [
        ArNSNameRecord(
          name: name,
          undername: '@',
          transactionId: 'tx',
          ttlSeconds: 300,
        ),
        ArNSNameRecord(
          name: name,
          undername: 'blog',
          transactionId: 'tx',
          ttlSeconds: 300,
        ),
      ],
    );

/// The Names page as a table of names, in the list pages' frame.
void main() {
  late _MockConfigService config;
  late _MockNamesCubit names;
  late _MockWalletCubit wallet;
  late AppRouterDelegate delegate;

  setUp(() {
    config = _MockConfigService();
    when(() => config.config).thenReturn(AppConfig(
      stripePublishableKey: '',
      allowedDataItemSizeForTurbo: 100,
      enableArNS: true,
    ));
    names = _MockNamesCubit();
    whenListen(
      names,
      const Stream<ArNSNamesState>.empty(),
      initialState: ArNSNamesState(
        status: ArNSNamesStatus.loaded,
        address: 'sol',
        names: [
          _name('studio', leaseLeft: const Duration(days: 12, hours: 3)),
          _name('maya'),
        ],
      ),
    );
    wallet = _MockWalletCubit();
    whenListen(
      wallet,
      const Stream<ArNSWalletState>.empty(),
      initialState: const ArNSWalletState(
        enabled: true,
        profileAddress: 'profile',
        linked: LinkedArNSWallet(address: 'sol', walletName: 'Phantom'),
      ),
    );
    delegate = AppRouterDelegate()..showingNames = true;
  });

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
              BlocProvider<ArNSNamesCubit>.value(value: names),
              BlocProvider<ArNSWalletCubit>.value(value: wallet),
            ],
            child: const Scaffold(body: ArNSNamesBody()),
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

  testWidgets('a table of names: bare, undernames used, lease ends',
      (tester) async {
    await pump(tester);

    for (final heading in ['Name', 'Undernames', 'Lease ends']) {
      expect(find.text(heading), findsOneWidget);
    }
    expect(find.text('maya'), findsOneWidget);
    expect(find.text('studio'), findsOneWidget);
    expect(find.text('1 of 10'), findsNWidgets(2));
    expect(find.text('Never'), findsOneWidget);
    expect(find.text('Ends in 12 days'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Ends in 12 days'),
        matching: find.byType(ArDriveStatusText),
      ),
      findsOneWidget,
      reason: 'said as status text, not a boxed tag',
    );
    // Sorted by name.
    expect(
      tester.getTopLeft(find.text('maya')).dy,
      lessThan(tester.getTopLeft(find.text('studio')).dy),
    );
  });

  testWidgets('a click shows the name in a details panel', (tester) async {
    await pump(tester);
    final pointer = await mouse(tester);

    await click(tester, pointer, 'studio');
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.byType(ArNSNameDetailsPanel), findsOneWidget);
    expect(find.text('studio.ar.io'), findsWidgets);
    expect(delegate.shownName, isNull, reason: 'a click only chooses');
  });

  Future<void> choose(WidgetTester tester, String name) async {
    final pointer = await mouse(tester);
    await click(tester, pointer, name);
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
  }

  Finder toolbarAction(String tooltip) => find.descendant(
        of: find.byType(DetailsPanelToolbarFrame),
        matching: find.ancestor(
          of: find.byTooltip(tooltip),
          matching: find.byType(ArDriveIconButton),
        ),
      );

  /// The file details panel's shape: the actions are icon buttons in the
  /// toolbar above the name; there are no buttons under the details.
  testWidgets("the panel's actions are icon buttons in its toolbar",
      (tester) async {
    await pump(tester);
    await choose(tester, 'studio');

    expect(toolbarAction('Open'), findsOneWidget);
    expect(toolbarAction('Renew'), findsOneWidget);
    expect(
      tester.getTopLeft(toolbarAction('Open')).dx,
      lessThan(tester.getTopLeft(toolbarAction('Renew')).dx),
    );
    expect(
      tester.getTopLeft(toolbarAction('Open')).dy,
      lessThan(tester.getTopLeft(find.text('studio.ar.io').first).dy),
      reason: 'above the name',
    );
    expect(
      find.descendant(
        of: find.byType(ArNSNameDetailsPanel),
        matching: find.byType(ArDriveButtonNew),
      ),
      findsNothing,
      reason: 'no buttons left under the details',
    );

    await tester.tap(toolbarAction('Open'));
    await tester.pump();
    expect(delegate.shownName, 'studio', reason: "Open opens the name's page");
  });

  testWidgets('a permanent name has nothing to renew', (tester) async {
    await pump(tester);
    await choose(tester, 'maya');

    expect(toolbarAction('Open'), findsOneWidget);
    expect(find.byTooltip('Renew'), findsNothing);
  });

  /// One label and value grid: every value ends on the same right edge,
  /// the lease's status text included, which used to sit on the left.
  testWidgets("the panel's values line up on the right", (tester) async {
    await pump(tester);
    await choose(tester, 'studio');

    final panel = find.byType(ArNSNameDetailsPanel);
    double right(Finder f) =>
        tester.getTopRight(find.descendant(of: panel, matching: f).first).dx;
    final lease = right(find.byType(ArDriveStatusText));
    final undernames = right(find.text('1 of 10'));
    final link = right(find.byType(CopyButton));

    expect(lease, moreOrLessEquals(undernames, epsilon: 1));
    expect(link, moreOrLessEquals(undernames, epsilon: 1));
  });

  testWidgets("a double-click opens the name's page", (tester) async {
    await pump(tester);
    final pointer = await mouse(tester);

    await click(tester, pointer, 'maya');
    await tester.pump(const Duration(milliseconds: 100));
    await click(tester, pointer, 'maya');

    expect(delegate.showingNames, isTrue);
    expect(delegate.shownName, 'maya');
  });

  testWidgets('no checkboxes: names have no bulk actions', (tester) async {
    // Checkboxes only where there is something to do with several rows at
    // once: the explorer and Your drives. Not on hover, not on a long press.
    await pump(tester);
    final pointer = await mouse(tester);
    await pointer.moveTo(tester.getCenter(find.text('maya')));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('maya'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byType(ArNSNameRow), findsWidgets);
    expect(find.byType(ArDriveCheckBox), findsNothing);
    expect(find.byType(ArDriveMultiSelectBox), findsNothing);
  });

  testWidgets('no grey intro sentence under the title', (tester) async {
    await pump(tester);

    expect(find.textContaining('what each points to'), findsNothing);
    expect(find.text('Get a name'), findsOneWidget);
  });

  testWidgets('Get a name says it opens a new window', (tester) async {
    // It opens the ar.io Console, outside the app: the new-window icon goes
    // after the label, as on every other link that leaves the app.
    await pump(tester);

    final button = find.ancestor(
      of: find.text('Get a name'),
      matching: find.byType(ArDriveButtonNew),
    );
    expect(button, findsOneWidget);
    expect(
      find.descendant(
        of: button,
        matching: find.byWidgetPredicate(
          (w) => w is ArDriveIcon && w.icon == ArDriveIconsData.new_window,
        ),
      ),
      findsOneWidget,
    );
    // After the label, not before it.
    expect(
      tester.getCenter(find.text('Get a name')).dx,
      lessThan(tester
          .getCenter(find.descendant(
            of: button,
            matching: find.byType(ArDriveIcon),
          ))
          .dx),
    );
  });
  group('a name the wallet controls but does not own', () {
    // Said once, in the name's details, not as a tag on every row: the row
    // tag ("Managed for its owner") was clutter, and it read oddly.
    setUp(() {
      whenListen(
        names,
        const Stream<ArNSNamesState>.empty(),
        initialState: ArNSNamesState(
          status: ArNSNamesStatus.loaded,
          address: 'sol',
          names: [
            _name('studio', role: ArNSRole.controller),
            _name('maya'),
          ],
        ),
      );
    });

    testWidgets('carries no tag in the list', (tester) async {
      await pump(tester);

      expect(find.text('studio'), findsOneWidget);
      expect(find.byType(ArDriveTag), findsNothing);
      expect(find.text('Managed for its owner'), findsNothing);
      expect(find.text('Controller'), findsNothing);
    });

    testWidgets('says its role once, in the details panel', (tester) async {
      await pump(tester);
      final pointer = await mouse(tester);

      await click(tester, pointer, 'studio');
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      final panel = find.byType(ArNSNameDetailsPanel);
      expect(panel, findsOneWidget);
      expect(find.descendant(of: panel, matching: find.text('Role')),
          findsOneWidget);
      expect(find.descendant(of: panel, matching: find.text('Controller')),
          findsOneWidget);
      expect(find.descendant(of: panel, matching: find.byType(ArDriveTag)),
          findsNothing);
    });

    testWidgets('a name the wallet owns has no role row', (tester) async {
      await pump(tester);
      final pointer = await mouse(tester);

      await click(tester, pointer, 'maya');
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      final panel = find.byType(ArNSNameDetailsPanel);
      expect(panel, findsOneWidget);
      expect(find.descendant(of: panel, matching: find.text('Role')),
          findsNothing);
    });
  });
}
