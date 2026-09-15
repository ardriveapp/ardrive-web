import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/utils/get_signature_headers_for_turbo.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockArDriveHTTP extends Mock implements ArDriveHTTP {}

class _MockSignatureHeaders extends Mock
    implements TurboSignatureHeadersManager {}

/// Finding credits on the wallet somebody signed in with.
///
/// Signing in with Phantom or MetaMask derives a deterministic Arweave wallet,
/// and that derived address is the ArDrive account. Turbo keeps a balance per
/// chain, so credits bought in Turbo's own console against the sign-in wallet
/// land somewhere ArDrive never looked: it only ever asked
/// `/v1/account/balance/arweave`.
void main() {
  group('classifying the wallet somebody signed in with', () {
    test('an 0x address is Ethereum', () {
      expect(
        walletTypeOfSourceAddress('0x1234abcd'),
        WalletType.ethereum,
      );
    });

    test('anything else that exists is Solana', () {
      expect(
        walletTypeOfSourceAddress('4WkBm7vD1qF9xYz'),
        WalletType.solana,
      );
    });

    /// An Arweave sign-in has no source wallet, and nothing to look up.
    test('and no source address is nobody to ask about', () {
      expect(walletTypeOfSourceAddress(null), isNull);
    });
  });

  group('asking Turbo about an address on another chain', () {
    late _MockArDriveHTTP http;
    late PaymentService service;

    setUp(() {
      http = _MockArDriveHTTP();
      service = PaymentService(
        httpClient: http,
        turboPaymentUri: Uri.parse('https://payment.test'),
        turboSignatureHeadersManager: _MockSignatureHeaders(),
      );
    });

    void answers(String body) {
      when(() => http.get(url: any(named: 'url'))).thenAnswer(
        (_) async => ArDriveHTTPResponse(
          data: body,
          statusCode: 200,
          retryAttempts: 0,
        ),
      );
    }

    test('asks the namespace for that chain, not arweave', () async {
      answers('{"effectiveBalance":"500"}');

      await service.getBalanceForAddress(
        address: '4WkBm7vD1qF9xYz',
        walletType: WalletType.solana,
      );

      final url = verify(() => http.get(url: captureAny(named: 'url')))
          .captured
          .single as String;

      expect(url, contains('/v1/account/balance/solana'));
      expect(url, contains('address=4WkBm7vD1qF9xYz'));
      expect(
        url,
        isNot(contains('balance/arweave')),
        reason: 'asking the arweave namespace about a Solana address is the '
            'bug this exists to answer',
      );
    });

    test('and the ethereum namespace for an 0x address', () async {
      answers('{"effectiveBalance":"1"}');

      await service.getBalanceForAddress(
        address: '0xabc',
        walletType: WalletType.ethereum,
      );

      final url = verify(() => http.get(url: captureAny(named: 'url')))
          .captured
          .single as String;

      expect(url, contains('/v1/account/balance/ethereum'));
    });

    test('reads the balance it is given', () async {
      answers('{"effectiveBalance":"12080000000000"}');

      expect(
        await service.getBalanceForAddress(
          address: '4WkBm',
          walletType: WalletType.solana,
        ),
        BigInt.parse('12080000000000'),
      );
    });

    /// 404 is how Turbo says "no such account", and for this question that is
    /// the same answer as "nothing there" - not a failure worth propagating.
    test('an account Turbo has never seen holds nothing', () async {
      when(() => http.get(url: any(named: 'url'))).thenThrow(
        ArDriveHTTPException(
          statusCode: 404,
          retryAttempts: 0,
          exception: Exception('not found'),
        ),
      );

      expect(
        await service.getBalanceForAddress(
          address: '4WkBm',
          walletType: WalletType.solana,
        ),
        BigInt.zero,
      );
    });

    /// Anything else is a real failure. The caller stays silent rather than
    /// reporting a balance nobody confirmed.
    test('but a real failure is not a zero balance', () async {
      when(() => http.get(url: any(named: 'url'))).thenThrow(
        ArDriveHTTPException(
          statusCode: 500,
          retryAttempts: 0,
          exception: Exception('gateway'),
        ),
      );

      expect(
        () => service.getBalanceForAddress(
          address: '4WkBm',
          walletType: WalletType.solana,
        ),
        throwsA(isA<ArDriveHTTPException>()),
      );
    });
  });
}
