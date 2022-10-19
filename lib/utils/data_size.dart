const int _aKibInBytes = 1024;
const int _aMibInBytes = _aKibInBytes * 1024;
const int _aGibInBytes = _aMibInBytes * 1024;

abstract class Base2DataSize {
  int get size;
}

class KiB implements Base2DataSize {
  KiB(this._size);

  final double _size;

  @override
  int get size => (_size * _aKibInBytes).toInt();
}

class MiB implements Base2DataSize {
  MiB(this._size);

  final double _size;

  @override
  int get size => (_size * _aMibInBytes).toInt();
}

class GiB implements Base2DataSize {
  GiB(this._size);

  final double _size;

  @override
  int get size => (_size * _aGibInBytes).toInt();
}
