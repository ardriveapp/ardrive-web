import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/services/arconnect/arconnect_prompt.dart';
import 'package:ardrive/services/arconnect/arconnect_wallet.dart';
import 'package:arweave/utils.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/utils.dart';

void main() {
  late MockArConnectService wander;

  setUpAll(() => registerFallbackValue(Uint8List(0)));

  setUp(() {
    ArConnectPrompt.reset();
    wander = MockArConnectService();
    when(() => wander.isExtensionPresent()).thenReturn(true);
  });

  tearDown(ArConnectPrompt.reset);

  group('a Wander wallet loaded from a saved account', () {
    test('knows its owner and address without asking Wander', () async {
      final owner = await getTestWallet().getOwner();
      final wallet = ArConnectWallet(wander, publicKey: owner);

      expect(await wallet.getOwner(), owner);
      expect(await wallet.getAddress(), await ownerToAddress(owner));
      verifyZeroInteractions(wander);
    });

    test('a signature Wander never gives ends in the Try again prompt', () {
      fakeAsync((async) {
        when(() => wander.getSignature(any()))
            .thenAnswer((_) => Completer<Uint8List>().future);
        final prompts = <ArConnectUnavailableReason>[];
        ArConnectPrompt.registerRetryPrompt((reason) async {
          prompts.add(reason);
          return false;
        });

        Object? error;
        ArConnectWallet(wander, publicKey: 'key')
            .sign(Uint8List(4))
            .catchError((Object e) {
          error = e;
          return Uint8List(0);
        });
        async.elapse(ArConnectPrompt.signTimeout * 2);

        expect(prompts, [ArConnectUnavailableReason.noAnswer]);
        expect(error, isA<ArConnectUnavailableException>());
      });
    });

    test('Try again asks for the signature again', () {
      fakeAsync((async) {
        var calls = 0;
        when(() => wander.getSignature(any())).thenAnswer((_) => calls++ == 0
            ? Completer<Uint8List>().future
            : Future.value(Uint8List.fromList([1, 2, 3])));
        ArConnectPrompt.registerRetryPrompt((_) async => true);

        Uint8List? signature;
        ArConnectWallet(wander, publicKey: 'key')
            .sign(Uint8List(4))
            .then((value) => signature = value);
        async.elapse(ArConnectPrompt.signTimeout * 2);

        expect(signature, [1, 2, 3]);
      });
    });
  });

  test('a wallet being connected at login asks Wander for its address',
      () async {
    when(() => wander.getWalletAddress()).thenAnswer((_) async => 'address');

    expect(await ArConnectWallet(wander).getAddress(), 'address');
  });
}
