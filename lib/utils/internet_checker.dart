import 'package:connectivity_plus/connectivity_plus.dart';

class InternetChecker {
  InternetChecker({required this.connectivity});

  final Connectivity connectivity;

  Future<bool> isConnected() async {
    final connectivityResult = await connectivity.checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }
}
