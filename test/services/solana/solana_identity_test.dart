import 'dart:typed_data';

import 'package:ardrive/services/solana/solana_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('deriveMnemonicFromSolanaSignature', () {
    test('produces a valid 12-word mnemonic', () async {
      final signature = Uint8List.fromList(List.filled(64, 42));
      final mnemonic = await deriveMnemonicFromSolanaSignature(signature);

      final words = mnemonic.split(' ');
      expect(words.length, 12);
    });

    test('produces deterministic output for the same signature', () async {
      final signature = Uint8List.fromList(List.filled(64, 99));

      final mnemonic1 = await deriveMnemonicFromSolanaSignature(signature);
      final mnemonic2 = await deriveMnemonicFromSolanaSignature(signature);

      expect(mnemonic1, equals(mnemonic2));
    });

    test('produces different mnemonics for different signatures', () async {
      final sig1 = Uint8List.fromList(List.filled(64, 1));
      final sig2 = Uint8List.fromList(List.filled(64, 2));

      final mnemonic1 = await deriveMnemonicFromSolanaSignature(sig1);
      final mnemonic2 = await deriveMnemonicFromSolanaSignature(sig2);

      expect(mnemonic1, isNot(equals(mnemonic2)));
    });

    test('solanaIdentityMessage contains ArDrive Identity v1', () {
      expect(solanaIdentityMessage, contains('ArDrive Identity v1'));
      expect(solanaIdentityMessage, contains('gateway you trust'));
    });
  });
}
