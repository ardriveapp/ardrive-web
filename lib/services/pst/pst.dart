import 'implementations/pst_stub.dart'
    if (dart.library.html) 'implementations/pst_web.dart' as implementation;

class PstService {
  /// Randomly returns an address for the holder of the app PST weighted by their holdings.
  Future<String> getWeightedPstHolder() =>
      implementation.getWeightedPstHolder();
}
