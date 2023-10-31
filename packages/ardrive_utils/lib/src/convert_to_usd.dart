import 'package:ardrive_http/ardrive_http.dart';

Future<double?> getArUsdConversionRateOrNull() async {
  try {
    return await getArUsdConversionRate();
  } catch (e) {
    return null;
  }
}

Future<double> getArUsdConversionRate() async {
  const String coinGeckoApi =
      'https://api.coingecko.com/api/v3/simple/price?ids=arweave&vs_currencies=usd';

  final response = await ArDriveHTTP(retries: 3).getJson(coinGeckoApi);

  return response.data?['arweave']['usd'];
}
