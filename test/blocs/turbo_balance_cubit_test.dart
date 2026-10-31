import 'dart:async';

// Importing necessary packages and files
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/topup/blocs/turbo_balance/turbo_balance_cubit.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/utils.dart';

class MockPaymentService extends Mock implements PaymentService {}

void main() {
  late MockPaymentService mockPaymentService;
  late TurboBalanceCubit turboBalanceCubit;

  final wallet = getTestWallet();

  setUp(() {
    mockPaymentService = MockPaymentService();
    turboBalanceCubit = TurboBalanceCubit(
      paymentService: mockPaymentService,
      wallet: wallet,
    );
  });

  blocTest<TurboBalanceCubit, TurboBalanceState>(
    'emits [TurboBalanceLoading, TurboBalanceSuccessState] when getBalance is successful',
    build: () {
      when(() => mockPaymentService.getBalance(wallet: wallet))
          .thenAnswer((_) async => Future.value(BigInt.from(100.0)));
      return turboBalanceCubit;
    },
    act: (cubit) => cubit.getBalance(),
    expect: () => [
      TurboBalanceLoading(),
      TurboBalanceSuccessState(balance: BigInt.from(100.0)),
    ],
  );

  blocTest<TurboBalanceCubit, TurboBalanceState>(
    'emits [TurboBalanceLoading, NewTurboUserState] when TurboUserNotFound is thrown',
    build: () {
      when(() => mockPaymentService.getBalance(wallet: wallet))
          .thenThrow(TurboUserNotFound());
      return turboBalanceCubit;
    },
    act: (cubit) => cubit.getBalance(),
    expect: () => [
      TurboBalanceLoading(),
      NewTurboUserState(),
    ],
  );

  blocTest<TurboBalanceCubit, TurboBalanceState>(
    'emits [TurboBalanceLoading, TurboBalanceErrorState] when an error is thrown',
    build: () {
      when(() => mockPaymentService.getBalance(wallet: wallet))
          .thenThrow(Exception());
      return turboBalanceCubit;
    },
    act: (cubit) => cubit.getBalance(),
    expect: () => [
      TurboBalanceLoading(),
      TurboBalanceErrorState(),
    ],
  );

  blocTest<TurboBalanceCubit, TurboBalanceState>(
    'a balance request that never answers ends in the error state',
    build: () {
      when(() => mockPaymentService.getBalance(wallet: wallet))
          .thenAnswer((_) => Completer<BigInt>().future);
      return TurboBalanceCubit(
        paymentService: mockPaymentService,
        wallet: wallet,
        requestTimeout: const Duration(milliseconds: 20),
      );
    },
    act: (cubit) => cubit.getBalance(),
    wait: const Duration(milliseconds: 100),
    expect: () => [
      TurboBalanceLoading(),
      TurboBalanceErrorState(),
    ],
  );

  // The profile card that asks for the balance can close while the request is
  // out or during the error's half-second wait, and a closed cubit throws on
  // emit ("Cannot emit new states after calling close").
  group('closed before the answer arrives', () {
    test('a balance that arrives after close is dropped', () async {
      when(() => mockPaymentService.getBalance(wallet: wallet))
          .thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return BigInt.from(100);
      });
      final pending = turboBalanceCubit.getBalance();
      await turboBalanceCubit.close();
      await expectLater(pending, completes);
    });

    test('an error that lands after close is dropped', () async {
      when(() => mockPaymentService.getBalance(wallet: wallet))
          .thenThrow(Exception());
      final pending = turboBalanceCubit.getBalance();
      await turboBalanceCubit.close();
      await expectLater(pending, completes);
    });
  });
}
