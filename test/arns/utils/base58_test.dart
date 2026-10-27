import 'dart:convert';

import 'package:ardrive/arns/utils/base58.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes a Solana address to its 32-byte key', () {
    final bytes = base58Decode('6eV7bK3bQJdd7Q44doWqAbnBCWNQRhB1HwCDGWf8Qe3V');

    expect(bytes, hasLength(32));
    // Checked against bs58.
    expect(
      base64Url.encode(bytes).replaceAll('=', ''),
      'U-S2eB9McpCmvlTx0fOqDhROa8Qk5582XPIJL3ZEhkw',
    );
  });

  test('leading 1s are leading zero bytes', () {
    expect(
        base58Decode('11111111111111111111111111111111'), List.filled(32, 0));
    expect(base58Decode('12'), [0, 1]);
  });

  test('rejects characters outside the alphabet', () {
    expect(() => base58Decode('0OIl'), throwsFormatException);
  });
}
