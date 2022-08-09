import 'dart:math';

import '../types/arweave_address.dart';

ArweaveAddress? weightedRandom(Map<ArweaveAddress, double> dict) {
  double sum = 0;
  final r = Random().nextDouble();

  for (final addr in dict.keys) {
    sum += dict[addr]!;
    if (r <= sum && dict[addr]! > 0) {
      return addr;
    }
  }

  return null;
}
