import 'implementations/pst_web.dart'
    if (dart.library.io) 'implementations/pst_stub.dart' as implementation;

export 'enums.dart';

class PstService {
  /// Returns the fee percentage of the app PST as a decimal percentage.
  Future<double> getPstFeePercentage() => implementation.getPstFeePercentage();

  /// Returns a randomly selected address for the holder of the app PST weighted by their holdings.
  Future<String> getWeightedPstHolder() =>
      implementation.getWeightedPstHolder();

  Future<BigInt> getPSTFee(BigInt uploadCost) async {
    return await implementation
        .getPstFeePercentage()
        .then((feePercentage) =>
            // Workaround [BigInt] percentage division problems
            // by first multiplying by the percentage * 100 and then dividing by 100.
            uploadCost * BigInt.from(feePercentage * 100) ~/ BigInt.from(100))
        .catchError((_) => BigInt.zero,
            test: (err) => err is UnimplementedError);
  }
}
