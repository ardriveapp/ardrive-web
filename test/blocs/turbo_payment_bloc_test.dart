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
            .thenAnswer((_) async => BigInt.zero);
      },
      act: (PaymentBloc bloc) {
        bloc.add(LoadInitialData());
      },
      expect: () {
        return [
          PaymentLoading(),
          PaymentLoaded(
            balance: BigInt.zero,
            estimatedStorage: 0,
            selectedAmount: 0,
            currencyUnit: 'usd',
            dataUnit: 'gb',
          ),
        ];
      },
    );

    test(
      'emits PriceUpdated state with updated price when UpdatePrice event is added',
      () {},
    );

    test(
      'emits PriceUpdated state with updated price when UnitChange event is added',
      () {},
    );

    test(
      'emits PriceQuoteLoaded state when ReadyForPayment event is added',
      () {},
    );

    test(
      'emits PriceQuoteLoaded state every 30s if last event was ReadyForPayment',
      () {},
    );

    test(
      'emits FormErrorState state when ConfirmPayment event is added and form is invalid',
      () {},
    );

    test(
      'emits PaymentSuccess state when ConfirmPayment event is added and payment is successful',
      () {},
    );

    test(
      'emits PaymentFailed state when ConfirmPayment event is added and payment is unsuccessful',
      () {},
    );
  });
}
