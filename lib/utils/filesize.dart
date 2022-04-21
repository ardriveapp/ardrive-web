import 'dart:math';

/// A method returns a human readable string representing a file _size
String filesize(dynamic size, [int round = 2]) {
  /** 
   * [size] can be passed as number or as string
   *
   * the optional parameter [round] specifies the number 
   * of digits after comma/point (default is 2)
   */
  final divider = pow(2, 10);
  int _size;
  try {
    _size = int.parse(size.toString());
  } catch (e) {
    throw ArgumentError('Can not parse the size parameter: $e');
  }

  if (_size < divider) {
    return '$_size B';
  }

  if (_size < pow(divider, 2) && _size % divider == 0) {
    return '${(_size / divider).toStringAsFixed(0)} KiB';
  }

  if (_size < pow(divider, 2)) {
    return '${(_size / divider).toStringAsFixed(round)} KiB';
  }

  if (_size < pow(divider, 3) && _size % pow(divider, 2) == 0) {
    return '${(_size / pow(divider, 2)).toStringAsFixed(0)} MiB';
  }

  if (_size < pow(divider, 3)) {
    return '${(_size / pow(divider, 2)).toStringAsFixed(round)} MiB';
  }

  if (_size < pow(divider, 4) && _size % pow(divider, 3) == 0) {
    return '${(_size / pow(divider, 3)).toStringAsFixed(0)} GiB';
  }

  if (_size < pow(divider, 4)) {
    return '${(_size / pow(divider, 3)).toStringAsFixed(round)} GiB';
  }

  if (_size < pow(divider, 5) && _size % pow(divider, 4) == 0) {
    final num r = _size / pow(divider, 4);
    return '${r.toStringAsFixed(0)} TiB';
  }

  if (_size < pow(divider, 5)) {
    final num r = _size / pow(divider, 4);
    return '${r.toStringAsFixed(round)} TiB';
  }

  if (_size < pow(divider, 6) && _size % pow(divider, 5) == 0) {
    final num r = _size / pow(divider, 5);
    return '${r.toStringAsFixed(0)} PiB';
  } else {
    final num r = _size / pow(divider, 5);
    return '${r.toStringAsFixed(round)} PiB';
  }
}
