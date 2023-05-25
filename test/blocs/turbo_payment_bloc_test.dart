// Importing necessary packages and files
import 'package:ardrive/blocs/turbo_payment/file_size_units.dart';
import 'package:ardrive/blocs/turbo_payment/turbo_payment_bloc.dart';
import 'package:ardrive/services/turbo/payment_service.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/utils.dart';

class MockPaymentService extends Mock implements PaymentService {}

const oneAR = 1000000000000;

void main() {
  final Wallet wallet = getTestWallet();

  late MockPaymentService mockPaymentService;
  late PaymentBloc paymentBloc;

  setUp(() {
    mockPaymentService = MockPaymentService();

    paymentBloc = PaymentBloc(
      paymentService: mockPaymentService,
      wallet: wallet,
    );
  });

  blocTest<PaymentBloc, PaymentState>(
    'emits [PaymentLoading, PaymentLoaded] when LoadInitialData is called',
    setUp: () {
      when(
        () => mockPaymentService.getBalance(
          wallet: wallet,
        ),
      ).thenAnswer((_) async => BigInt.from(oneAR * 2));
      when(
        () => mockPaymentService.getPriceForFiat(
          currency: 'usd',
          amount: 25,
        ),
      ).thenAnswer((_) async => BigInt.from(oneAR));
      when(
        () => mockPaymentService.getPriceForBytes(
          byteSize: oneGigbyteInBytes,
        ),
      ).thenAnswer((_) async => BigInt.from(oneAR));
    },
    build: () {
      return paymentBloc;
    },
    act: (bloc) => bloc.add(LoadInitialData()),
    expect: () => [
      PaymentLoading(),
      PaymentLoaded(
        balance: BigInt.from(oneAR * 2),
        estimatedStorageForBalance: '2.00',
        selectedAmount: 25.0,
        creditsForSelectedAmount: BigInt.from(oneAR),
        estimatedStorageForSelectedAmount: '1.00',
        currencyUnit: 'usd',
        dataUnit: FileSizeUnit.gigabytes,
      ),
    ],
  );

  blocTest<PaymentBloc, PaymentState>(
    'emits [PaymentLoading, PaymentLoaded] when FiatAmountSelected is called',
    setUp: () {
      paymentBloc.costOfOneGb = BigInt.from(oneAR);

      when(
        () => mockPaymentService.getBalance(wallet: wallet),
      ).thenAnswer((_) async => BigInt.from(oneAR * 2));
      when(
        () =>
            mockPaymentService.getPriceForFiat(currency: 'usd', amount: 150.0),
      ).thenAnswer((_) async => BigInt.from(oneAR * 3));
    },
    build: () {
      return paymentBloc;
    },
    act: (bloc) => bloc.add(FiatAmountSelected(150.0)),
    expect: () => [
      PaymentLoading(),
      PaymentLoaded(
        balance: BigInt.from(oneAR * 2),
        estimatedStorageForBalance: '2.00',
        selectedAmount: 150.0,
        creditsForSelectedAmount: BigInt.from(oneAR * 3),
        estimatedStorageForSelectedAmount: '3.00',
        currencyUnit: 'usd',
        dataUnit: FileSizeUnit.gigabytes,
      ),
    ],
  );
  blocTest<PaymentBloc, PaymentState>(
    'emits [PaymentLoading, PaymentLoaded] when CurrencyUnitChanged is called',
    setUp: () {
      paymentBloc.costOfOneGb = BigInt.from(oneAR);

      when(() => mockPaymentService.getBalance(wallet: wallet))
          .thenAnswer((_) async => BigInt.from(oneAR));
      when(() => mockPaymentService.getPriceForFiat(
            currency: 'cad',
            amount: presetAmounts.first.toDouble(),
          )).thenAnswer((_) async => BigInt.from(oneAR * 0.5));
      when(() =>
              mockPaymentService.getPriceForBytes(byteSize: oneGigbyteInBytes))
          .thenAnswer((_) async => BigInt.from(oneAR));
    },
    build: () {
      return paymentBloc;
    },
    act: (bloc) => bloc.add(CurrencyUnitChanged('cad')),
    expect: () => [
      PaymentLoading(),
      PaymentLoaded(
        balance: BigInt.from(oneAR),
        estimatedStorageForBalance: '1.00',
        selectedAmount: presetAmounts.first.toDouble(),
        creditsForSelectedAmount: BigInt.from(oneAR * 0.5),
        estimatedStorageForSelectedAmount: '0.50',
        currencyUnit: 'cad',
        dataUnit: FileSizeUnit.gigabytes,
      ),
    ],
  );

  blocTest<PaymentBloc, PaymentState>(
    'emits [PaymentLoading, PaymentLoaded] when DataUnitChanged is called',
    setUp: () {
      paymentBloc.costOfOneGb = BigInt.from(oneAR);

      when(() => mockPaymentService.getBalance(wallet: wallet))
          .thenAnswer((_) async => BigInt.from(oneAR));
      when(() =>
              mockPaymentService.getPriceForFiat(currency: 'usd', amount: 25.0))
          .thenAnswer((_) async => BigInt.from(oneAR));
      when(() =>
              mockPaymentService.getPriceForBytes(byteSize: oneGigbyteInBytes))
          .thenAnswer((_) async => BigInt.from(oneAR));
    },
    build: () {
      return paymentBloc;
    },
    act: (bloc) => bloc.add(DataUnitChanged(FileSizeUnit.megabytes)),
    expect: () {
      return [
        PaymentLoading(),
        PaymentLoaded(
          balance: BigInt.from(oneAR),
          estimatedStorageForBalance: '1024.00',
          selectedAmount: 25.0,
          creditsForSelectedAmount: BigInt.from(oneAR),
          estimatedStorageForSelectedAmount: '1024.00',
          currencyUnit: 'usd',
          dataUnit: FileSizeUnit.megabytes,
        ),
      ];
    },
  );

  blocTest<PaymentBloc, PaymentState>(
    'emits [] when AddCreditsClicked is called',
    build: () => paymentBloc,
    act: (bloc) => bloc.add(AddCreditsClicked()),
    expect: () => [],
  );
}
