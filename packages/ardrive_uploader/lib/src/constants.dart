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
