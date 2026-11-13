import 'package:ardrive/turbo/topup/views/topup_modal.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:flutter_test/flutter_test.dart';

/// The modal tells its caller about a payment once, when it closes. Only the
/// card path sets the session's payment status, so the crypto path reports
/// itself; without that Billing and the profile balance stayed stale.
void main() {
  test('a card payment is a success', () {
    expect(
      turboTopupSucceeded(
          cardStatus: PaymentStatus.success, paidByCrypto: false),
      isTrue,
    );
  });

  test('a crypto payment is a success without a card status', () {
    expect(turboTopupSucceeded(cardStatus: null, paidByCrypto: true), isTrue);
  });

  test('closing without paying is not a success', () {
    expect(turboTopupSucceeded(cardStatus: null, paidByCrypto: false), isFalse);
    expect(
      turboTopupSucceeded(
          cardStatus: PaymentStatus.failed, paidByCrypto: false),
      isFalse,
    );
  });
}
