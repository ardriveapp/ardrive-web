import 'dart:math';

import 'package:ardrive_utils/ardrive_utils.dart';

ArweaveAddress? weightedRandom(
  Map<ArweaveAddress, double> dict, {
  double? testingRandom, // for testing purposes only
}) {
  double sum = 0;
  final r = testingRandom ?? Random().nextDouble();

  for (final addr in dict.keys) {
    sum += dict[addr]!;
    if (r <= sum && dict[addr]! > 0) {
      return addr;
    }
  }

  return null;
}
