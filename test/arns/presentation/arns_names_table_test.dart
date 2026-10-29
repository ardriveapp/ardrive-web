import 'package:ardrive/arns/data/arns_wallet_store.dart';
import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/arns/presentation/names/arns_names_cubit.dart';
import 'package:ardrive/arns/presentation/names_page/names_page.dart';
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
    expect(find.text('Renew'), findsOneWidget);
    expect(delegate.shownName, isNull, reason: 'a click only chooses');
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

  testWidgets('no grey intro sentence under the title', (tester) async {
    await pump(tester);

    expect(find.textContaining('what each points to'), findsNothing);
    expect(find.text('Get a name'), findsOneWidget);
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
