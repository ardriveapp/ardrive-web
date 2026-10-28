import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/arns/presentation/names/arns_names_cubit.dart';
import 'package:ardrive/arns/presentation/names_page/names_page.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/services/config/config.dart';
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

ArNSNameRecord _record(String undername) => ArNSNameRecord(
      name: 'studio',
      undername: undername,
      transactionId: 'Zvp8dEkO3nQ2wX9yV8uT7sR6qP5oN4mL3kJ2iH1gF0c',
      ttlSeconds: 3600,
    );

final _studio = ArNSManagedName(
  name: 'studio',
  processId: 'ant-studio',
  role: ArNSRole.owner,
  type: ArNSNameType.lease,
  endTimestamp: DateTime.now().add(const Duration(days: 12)),
  undernameLimit: 100,
  records: [
    _record('@'),
    for (var i = 1; i <= 24; i++) _record('project-$i'),
  ],
);

void main() {
  late _MockConfigService config;
  late _MockNamesCubit names;
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
        names: [_studio],
      ),
    );
    delegate = AppRouterDelegate()
      ..showingNames = true
      ..shownName = 'studio';
  });

  Future<void> pump(WidgetTester tester, String name) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2000));
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
            ],
            child: Scaffold(body: ArNSNameView(name: name)),
          ),
        ),
      ),
    );
  }

  testWidgets('the full host is the title; rows say the undername alone',
      (tester) async {
    await pump(tester, 'studio');

    expect(find.text('studio.ar.io'), findsOneWidget);
    expect(find.text('studio'), findsOneWidget, reason: 'the name itself');
    expect(find.text('project-1'), findsOneWidget);
    expect(find.text('project-1_studio.ar.io'), findsNothing);
    // A page at a time.
    expect(find.text('project-10'), findsNothing);
  });

  testWidgets('Find an undername filters and starts at the first page',
      (tester) async {
    await pump(tester, 'studio');

    await tester.tap(find.byTooltip('Next page'));
    await tester.pump();
    expect(find.text('project-10'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'project');
    await tester.pump();
    expect(find.text('project-1'), findsOneWidget, reason: 'back on page 1');
    expect(find.text('studio'), findsNothing);

    await tester.enterText(find.byType(TextField), 'ject-2');
    await tester.pump();

    expect(find.text('project-2'), findsOneWidget);
    for (var i = 20; i <= 24; i++) {
      expect(find.text('project-$i'), findsOneWidget);
    }
    expect(find.text('project-1'), findsNothing);
    expect(find.text('studio'), findsNothing);

    await tester.enterText(find.byType(TextField), 'nothing-like-it');
    await tester.pump();
    expect(find.text('No undernames match.'), findsOneWidget);
  });

  testWidgets('the back link goes to every name', (tester) async {
    await pump(tester, 'studio');

    await tester.tap(find.text('Names'));
    await tester.pump();

    expect(delegate.showingNames, isTrue);
    expect(delegate.shownName, isNull);
  });

  testWidgets('a name the wallet does not have says so', (tester) async {
    await pump(tester, 'unknown');

    expect(find.text("This name isn't in your linked wallet."), findsOneWidget);
  });

  test('arnsRecordsMatching filters by literal name', () {
    final found = arnsRecordsMatching(_studio.records, ' PROJECT-1 ');
    expect(
      found.map((r) => r.undername),
      ['project-1', for (var i = 10; i <= 19; i++) 'project-$i'],
    );
    expect(arnsRecordsMatching(_studio.records, ''), _studio.records);
  });

  test('arnsShortLabel: the bare name for the name itself', () {
    expect(arnsShortLabel(_record('@')), 'studio');
    expect(arnsShortLabel(_record('blog')), 'blog');
  });
}
