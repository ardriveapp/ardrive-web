import 'package:ardrive/gar/presentation/bloc/gar_bloc.dart';
import 'package:ardrive/gar/presentation/widgets/gar_modal.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockGarBloc extends MockBloc<GarEvent, GarState> implements GarBloc {}

Gateway _gateway(String fqdn, String label) => Gateway(
      operatorStake: 1,
      gatewayAddress: 'addr-$fqdn',
      observerAddress: 'obs-$fqdn',
      settings: Settings(
        port: 443,
        protocol: 'https',
        allowDelegatedStaking: false,
        fqdn: fqdn,
        delegateRewardShareRatio: 0,
        properties: '',
        note: '',
        minDelegatedStake: 0,
        label: label,
        autoStake: false,
      ),
      startTimestamp: 0,
      totalDelegatedStake: 0,
      stats: Stats(
        failedConsecutiveEpochs: 0,
        observedEpochCount: 0,
        passedConsecutiveEpochs: 0,
        totalEpochCount: 0,
        prescribedEpochCount: 0,
        passedEpochCount: 0,
        failedEpochCount: 0,
      ),
      status: 'joined',
    );

/// The gateway list shows inside the gateway dialog, as standard rows, with
/// its failure as a notice and a retry, not as a dialog of its own.
void main() {
  late _MockGarBloc bloc;
  Gateway? picked;

  setUpAll(() => registerFallbackValue(GetGateways()));

  Future<void> pump(WidgetTester tester, GarState state) async {
    bloc = _MockGarBloc();
    picked = null;
    whenListen(bloc, const Stream<GarState>.empty(), initialState: state);
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ArIOGatewayPicker(
            createBloc: (_) => bloc,
            onSelected: (gateway) => picked = gateway,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('shows the gateways as choice rows and picks one',
      (tester) async {
    final a = _gateway('a.example.com', 'Alpha');
    await pump(
      tester,
      GatewaysLoaded(
          gateways: [a, _gateway('b.example.com', 'Beta')], currentGateway: a),
    );

    expect(find.byType(ArDriveChoiceItem), findsNWidgets(2));
    expect(find.byType(ListTile), findsNothing);
    expect(find.byType(Dialog), findsNothing);

    await tester.tap(find.text('Beta (b.example.com)'));
    expect(picked?.settings.fqdn, 'b.example.com');
  });

  testWidgets('a load failure is a notice with Try again', (tester) async {
    await pump(tester, const GatewaysError());

    expect(find.byType(ArDriveNotice), findsOneWidget);
    expect(find.text('Couldn\'t load gateways'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    // Once when it opened, once for the retry.
    verify(() => bloc.add(any(that: isA<GetGateways>()))).called(2);
  });
}
