// ignore_for_file: constant_identifier_names

const int _aKibInBytes = 1024;
const int _aMibInBytes = _aKibInBytes * 1024;
const int _aGibInBytes = _aMibInBytes * 1024;

abstract class Base2DataSize {
  int get size;
}

class KiB implements Base2DataSize {
  const KiB(this._size) : assert(_size >= 0);

  final int _size;

  @override
  int get size => _size * _aKibInBytes;
}

class MiB implements Base2DataSize {
  const MiB(this._size) : assert(_size >= 0);

  final int _size;

  @override
  int get size => _size * _aMibInBytes;
}

class GiB implements Base2DataSize {
  const GiB(this._size) : assert(_size >= 0);

  final int _size;

  @override
  int get size => _size * _aGibInBytes;
}

const int FIVE_GIBIBYTES = 5 * 1024 * 1024 * 1024;

const int TWENTY_MEGABITES = 20 * 1024 * 1024;
