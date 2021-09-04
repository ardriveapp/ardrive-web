import 'implementations/pst_web.dart'
    if (dart.library.io) 'implementations/pst_verto_cache.dart' as implementation;

export 'enums.dart';

class PstService {
  /// Returns the fee percentage of the app PST as a decimal percentage.
  Future<double> getPstFeePercentage() => implementation.getPstFeePercentage();

  /// Returns a randomly selected address for the holder of the app PST weighted by their holdings.
  Future<String> getWeightedPstHolder() =>
      implementation.getWeightedPstHolder();
}
