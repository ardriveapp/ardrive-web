import 'package:ardrive_utils/ardrive_utils.dart';

final int maxSizeSupportedByGCMEncryption = MiB(100).size;

final uContractId =
    TransactionID('KTzTXT_ANmF84fWEKHzWURD1LWd9QaFR9yfYUwH2Lxw');

const List<String> supportedImageTypesForThumbnails = [
  'image/jpeg',
  'image/png',
  'image/gif',
  'image/webp',
  'image/bmp',
];

/// ARNS resolver base URL (e.g. https://ar.io). Use for building resolver URLs
/// (e.g. https://ao.ar.io).
const String arnsResolverUrl = 'https://ar.io';

/// Builds the ARNS resolver URL for [name] using [arnsResolverUrl] as the base
/// (e.g. name "ao" with base https://ar.io → https://ao.ar.io).
/// Uses URI parsing for safe construction.
String resolveArnsNameUrl(String name) {
  final base = Uri.parse(arnsResolverUrl);
  return base.replace(host: '$name.${base.host}').toString();
}
