import 'dart:typed_data';

import 'package:ardrive/arns/data/bridge_arns_owner_signer.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockArioSDK extends Mock implements ArioSDK {}

void main() {
  late _MockArioSDK sdk;
  late BridgeArNSOwnerSigner signer;

  setUp(() {
    sdk = _MockArioSDK();
    signer = BridgeArNSOwnerSigner(arioSDK: sdk, address: 'linked');
    when(() => sdk.solanaSignMessage(any()))
        .thenAnswer((_) async => Uint8List(64));
    when(() => sdk.solanaSignTransaction(any()))
        .thenAnswer((_) async => 'signed');
  });

  setUpAll(() => registerFallbackValue(Uint8List(0)));

  test('signs on the linked account', () async {
    when(() => sdk.connectedSolanaAddress).thenReturn('linked');

    expect(await signer.signMessage(Uint8List(1)), hasLength(64));
    expect(await signer.signTransaction('tx'), 'signed');
  });

  test('refuses to sign on another account', () {
    when(() => sdk.connectedSolanaAddress).thenReturn('other');

    expect(
      () => signer.signMessage(Uint8List(1)),
      throwsA(isA<ArNSWrongAccountException>()),
    );
    expect(
      () => signer.signTransaction('tx'),
      throwsA(isA<ArNSWrongAccountException>()),
    );
    verifyNever(() => sdk.solanaSignMessage(any()));
    verifyNever(() => sdk.solanaSignTransaction(any()));
  });
}
