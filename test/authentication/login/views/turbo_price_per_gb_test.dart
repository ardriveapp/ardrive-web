import 'dart:async';

import 'package:ardrive/authentication/login/views/tiles/tiles_view.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPaymentService extends Mock implements PaymentService {}

void main() {
  late _MockPaymentService payments;

  setUp(() {
    forgetTurboPricePerGb();
    payments = _MockPaymentService();
  });
  tearDown(forgetTurboPricePerGb);

  test('the price is Turbo\'s rate for 1 GiB, as the calculator shows',
      () async {
    when(() => payments.getUsdPerGiB()).thenAnswer((_) async => 76.03);
    expect(await turboPricePerGb(payments), 76.03);
    verifyNever(
        () => payments.getPriceForBytes(byteSize: any(named: 'byteSize')));
  });

  test('no price when Turbo fails, and the next read tries again', () async {
    when(() => payments.getUsdPerGiB()).thenThrow(Exception('down'));
    expect(await turboPricePerGb(payments), isNull);
    when(() => payments.getUsdPerGiB()).thenAnswer((_) async => 76.03);
    expect(await turboPricePerGb(payments), 76.03);
  });

  test('a read that stalls gives up after the timeout', () {
    fakeAsync((time) {
      when(() => payments.getUsdPerGiB())
          .thenAnswer((_) => Completer<double>().future);
      double? price = -1;
      var answered = false;
      turboPricePerGb(payments).then((p) {
        price = p;
        answered = true;
      });
      time.elapse(pricePerGbTimeout - const Duration(milliseconds: 1));
      expect(answered, isFalse);
      time.elapse(const Duration(milliseconds: 2));
      expect(answered, isTrue);
      expect(price, isNull);
    });
  });
}
