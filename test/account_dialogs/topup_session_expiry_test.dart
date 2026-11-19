import 'dart:async';

import 'package:ardrive/turbo/topup/blocs/turbo_topup_flow_bloc.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockTurbo extends Mock implements Turbo {}

/// The 25-minute session running out replaces an unfinished payment with an
/// error, but not a result that is already on screen.
void main() {
  late _MockTurbo turbo;
  late StreamController<bool> expired;

  setUp(() {
    turbo = _MockTurbo();
    expired = StreamController<bool>.broadcast();
    when(() => turbo.onSessionExpired).thenAnswer((_) => expired.stream);
  });
  tearDown(() => expired.close());

  blocTest<TurboTopupFlowBloc, TurboTopupFlowState>(
    'an expiry after the payment succeeded leaves the success view',
    build: () => TurboTopupFlowBloc(turbo),
    act: (bloc) async {
      bloc.add(const TurboTopUpShowSuccessView(amountPaid: '\$25.00'));
      await Future<void>.delayed(Duration.zero);
      expired.add(true);
    },
    wait: const Duration(milliseconds: 50),
    expect: () => [isA<TurboTopupFlowShowingSuccessView>()],
  );

  blocTest<TurboTopupFlowBloc, TurboTopupFlowState>(
    'an expiry before the payment still shows the expired view',
    build: () => TurboTopupFlowBloc(turbo),
    act: (bloc) async {
      expired.add(true);
    },
    wait: const Duration(milliseconds: 50),
    expect: () => [isA<TurboTopupFlowShowingErrorView>()],
  );
}
