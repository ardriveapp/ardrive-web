import 'package:connectivity_plus/connectivity_plus.dart';

class InternetChecker {
  InternetChecker({required this.connectivity});

  final Connectivity connectivity;

  Future<bool> isConnected() async {
    final connectivityResult = await connectivity.checkConnectivity();

    /// According to the documentation, if no connection is available, the result will be [ConnectivityResult.none]
    final noneConnection = connectivityResult.first == ConnectivityResult.none;

    return !noneConnection;
  }
}
