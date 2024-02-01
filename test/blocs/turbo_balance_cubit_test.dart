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
}
