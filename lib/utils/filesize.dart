import 'dart:math';

/// A method returns a human readable string representing a file _size
String filesize(dynamic sizeToParse, [int round = 2]) {
  /** 
   * [size] in bytes, can be passed as number or as string
   *
   * the optional parameter [round] specifies the number 
   * of digits after comma/point (default is 2)
   */
  final divider = pow(2, 10);
  int size;
  try {
    size = int.parse(sizeToParse.toString());
  } catch (e) {
    throw ArgumentError('Can not parse the size parameter: $e');
  }

  if (size < divider) {
    return '$size B';
  }

  if (size < pow(divider, 2) && size % divider == 0) {
    return '${(size / divider).toStringAsFixed(0)} KiB';
  }

  if (size < pow(divider, 2)) {
    return '${(size / divider).toStringAsFixed(round)} KiB';
  }

  if (size < pow(divider, 3) && size % pow(divider, 2) == 0) {
    return '${(size / pow(divider, 2)).toStringAsFixed(0)} MiB';
  }

  if (size < pow(divider, 3)) {
    return '${(size / pow(divider, 2)).toStringAsFixed(round)} MiB';
  }

  if (size < pow(divider, 4) && size % pow(divider, 3) == 0) {
    return '${(size / pow(divider, 3)).toStringAsFixed(0)} GiB';
  }

  if (size < pow(divider, 4)) {
    return '${(size / pow(divider, 3)).toStringAsFixed(round)} GiB';
  }

  if (size < pow(divider, 5) && size % pow(divider, 4) == 0) {
    final num r = size / pow(divider, 4);
    return '${r.toStringAsFixed(0)} TiB';
  }

  if (size < pow(divider, 5)) {
    final num r = size / pow(divider, 4);
    return '${r.toStringAsFixed(round)} TiB';
  }

  if (size < pow(divider, 6) && size % pow(divider, 5) == 0) {
    final num r = size / pow(divider, 5);
    return '${r.toStringAsFixed(0)} PiB';
  } else {
    final num r = size / pow(divider, 5);
    return '${r.toStringAsFixed(round)} PiB';
  }
}
