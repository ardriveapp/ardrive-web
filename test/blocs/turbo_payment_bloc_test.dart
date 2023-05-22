import 'package:ardrive/blocs/turbo_payment/turbo_payment_bloc.dart';
import 'package:ardrive/services/turbo/payment_service.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockPaymentService extends Mock implements PaymentService {}

void main() async {
  final testWallet = await Wallet.generate();
  group('PaymentBloc', () {
    late PaymentBloc paymentBloc;
    late MockPaymentService mockPaymentService;

    setUp(() {
      mockPaymentService = MockPaymentService();
      paymentBloc = PaymentBloc(
        paymentService: mockPaymentService,
        wallet: testWallet,
      );
    });

    tearDown(() {
      paymentBloc.close();
    });

    blocTest(
      'emits PaymentLoaded state with initial balance data and supported currencies when LoadInitialData event is added',
      build: () => paymentBloc,
      setUp: () {
        when(() => mockPaymentService.getBalance(wallet: testWallet))
            .thenAnswer((_) async => BigInt.one);
        when(() => mockPaymentService.getPriceForFiat(
              currency: 'usd',
              amount: paymentBloc.currentAmount,
            )).thenAnswer((_) async => BigInt.one);
      },
      act: (PaymentBloc bloc) {
        bloc.add(LoadInitialData());
      },
      expect: () {
        return [
          PaymentLoading(),
          PaymentLoaded(
            balance: BigInt.one,
            estimatedStorageForBalance: 0,
            selectedAmount: 0,
            creditsForSelectedAmount: BigInt.one,
            estimatedStorageForSelectedAmount: 0,
            currencyUnit: 'usd',
            dataUnit: 'gb',
          ),
        ];
      },
    );

    blocTest(
      'emits PaymentLoaded state with initial balance data and supported currencies when selected amount is updated',
      build: () => paymentBloc,
      setUp: () {
        when(() => mockPaymentService.getBalance(wallet: testWallet))
            .thenAnswer((_) async => BigInt.one);
        when(() => mockPaymentService.getPriceForFiat(
              currency: 'usd',
              amount: 100,
            )).thenAnswer((_) async => BigInt.two);
      },
      act: (PaymentBloc bloc) {
        bloc.add(FiatAmountSelected(100));
      },
      expect: () {
        return [
          PaymentLoading(),
          PaymentLoaded(
            balance: BigInt.one,
            estimatedStorageForBalance: 0,
            selectedAmount: 0,
            creditsForSelectedAmount: BigInt.two,
            estimatedStorageForSelectedAmount: 0,
            currencyUnit: 'usd',
            dataUnit: 'gb',
          ),
        ];
      },
    );
  });
}
