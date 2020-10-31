import 'implementations/pst_stub.dart'
    if (dart.library.html) 'implementations/pst_web.dart' as implementation;

class PstService {
  /// Returns a randomly selected address for the holder of the app PST weighted by their holdings.
  Future<String> getWeightedPstHolder() =>
      implementation.getWeightedPstHolder();
}
