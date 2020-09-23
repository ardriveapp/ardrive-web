import 'dart:math';
import 'dart:typed_data';

final random = Random.secure();

Uint8List generateRandomBytes(int byteLength) =>
    Uint8List.fromList(List.generate(byteLength, (_) => random.nextInt(256)));
