import 'package:ardrive/services/config/config_service.dart';

/// See the web implementation.
///
/// Sharing credits needs a browser wallet extension to sign the grant, so off
/// the web there is nothing to sign with. [isSupported] is false and the payment
/// sheet falls back to naming the address and letting the reader share the
/// credits in Turbo themselves.
class CreditSharingService {
  CreditSharingService();

  factory CreditSharingService.fromConfig(ConfigService configService) =>
      CreditSharingService();

  bool get isSupported => false;

  Future<void> shareCreditsFromSignInWallet({
    required String approvedAddress,
    required BigInt approvedWinc,
  }) async {
    throw UnsupportedError('Credit sharing is only available on web platforms');
  }
}
