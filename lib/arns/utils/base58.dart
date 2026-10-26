import 'dart:typed_data';

const _alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

/// Decodes a base58 (Bitcoin alphabet) string, as Solana addresses use.
///
/// Throws [FormatException] on a character outside the alphabet.
Uint8List base58Decode(String input) {
  var value = BigInt.zero;
  final base = BigInt.from(58);
  for (final char in input.split('')) {
    final digit = _alphabet.indexOf(char);
    if (digit < 0) {
      throw FormatException('Not a base58 character', input);
    }
    value = value * base + BigInt.from(digit);
  }

  final bytes = <int>[];
  while (value > BigInt.zero) {
    bytes.add((value & BigInt.from(0xff)).toInt());
    value = value >> 8;
  }

  // Each leading '1' is a leading zero byte.
  for (final char in input.split('')) {
    if (char != '1') break;
    bytes.add(0);
  }

  return Uint8List.fromList(bytes.reversed.toList());
}
