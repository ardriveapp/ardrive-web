import 'implementations/pst_smartweave.dart' as smartweave;
import 'implementations/pst_verto.dart' as verto;

export 'enums.dart';

class PstService {
  /// Returns the fee percentage of the app PST as a decimal percentage.
  Future<double> getPstFeePercentage() {
    return verto.getPstFeePercentage().onError((error, stackTrace) {
      print('Cannot fetch pst fee from verto, falling back on smartweave');
      return smartweave.getPstFeePercentage();
    });
  }

  /// Returns a randomly selected address for the holder of the app PST weighted by their holdings.
  Future<String> getWeightedPstHolder() {
    return verto.getWeightedPstHolder().onError((error, stackTrace) {
      print('Cannot fetch pst fee from verto, falling back on smartweave');
      return smartweave.getWeightedPstHolder();
    });
  }

  Future<BigInt> getPSTFee(BigInt uploadCost) async {
    return await getPstFeePercentage()
        .then((feePercentage) =>
            // Workaround [BigInt] percentage division problems
            // by first multiplying by the percentage * 100 and then dividing by 100.
            uploadCost * BigInt.from(feePercentage * 100) ~/ BigInt.from(100))
        .catchError(
          (_) => BigInt.zero,
          test: (err) => err is UnimplementedError,
        );
  }
}
