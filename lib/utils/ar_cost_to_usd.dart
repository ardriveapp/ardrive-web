import 'package:ardrive/services/arweave/arweave.dart';

Future<double?> arCostToUsdOrNull(ArweaveService arweave, double arCost) async {
  final arUsdConversionRate = await arweave.getArUsdConversionRateOrNull();

  if (arUsdConversionRate == null) {
    return null;
  }

  return arCost * arUsdConversionRate;
}
