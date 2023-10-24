import 'package:arweave/utils.dart' as utils;

String convertCreditsToLiteralString(BigInt credits) {
  final creditsAsAr = convertWinstonToAr(credits);
  final creditsString = creditsAsAr.toStringAsFixed(4);

  return creditsString;
}

String convertARToLiteralString(BigInt ar) {
  final arString = utils.winstonToAr(ar).substring(0, 6);

  return arString;
}

double convertWinstonToAr(BigInt winston) {
  return winston / BigInt.from(1000000000000);
}
