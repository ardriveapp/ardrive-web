import 'package:ardrive/blocs/turbo_payment/turbo_payment_bloc.dart';
import 'package:ardrive/services/turbo/payment_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockPaymentService extends Mock implements PaymentService {}

void main() {
  group('PaymentBloc', () {
    late PaymentBloc paymentBloc;
    late MockPaymentService mockPaymentService;

    setUp(() {
      mockPaymentService = MockPaymentService();
      paymentBloc = PaymentBloc(mockPaymentService);
    });

    tearDown(() {
      paymentBloc.close();
    });

    test(
        'emits PaymentLoaded state with initial balance data and supported currencies when LoadInitialData event is added',
        () {
      final expectedInitialData = PaymentLoaded(
        balance: 0,
        estimatedStorage: 0,
        selectedAmount: 0,
        currencyUnit: '',
        dataUnit: '',
      );

      expectLater(paymentBloc,
          emitsInOrder([isA<PaymentInitial>(), expectedInitialData]));

      paymentBloc.add(LoadInitialData());
    });
  });

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
}
