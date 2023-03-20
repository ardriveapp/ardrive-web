class ArConnectConnectivitySingleton {
  static final ArConnectConnectivitySingleton _instance =
      ArConnectConnectivitySingleton._internal();

  factory ArConnectConnectivitySingleton() {
    return _instance;
  }

  ArConnectConnectivitySingleton._internal();

  final _arConnectConnectivity = ArConnectConnectivitySingleton();

  ArConnectConnectivitySingleton get arConnectConnectivity =>
      _arConnectConnectivity;
}
