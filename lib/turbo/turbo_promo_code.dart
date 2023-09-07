import 'package:ardrive/turbo/services/payment_service.dart';

abstract class TurboPromoCode {
  final PaymentService paymentService;

  const TurboPromoCode({
    required this.paymentService,
  });

  Future<double?> getPromoDiscountFactor(String promoCode);
}

class TurboPromoCodeImpl implements TurboPromoCode {
  @override
  final PaymentService paymentService;

  const TurboPromoCodeImpl({
    required this.paymentService,
  });

  @override
  Future<double?> getPromoDiscountFactor(String promoCode) =>
      paymentService.getPromoDiscountFactor(promoCode);
}
