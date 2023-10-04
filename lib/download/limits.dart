import 'package:ardrive/utils/data_size.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
// ignore: depend_on_referenced_packages
import 'package:device_info_plus/device_info_plus.dart';

import 'download_utils.dart';

final publicDownloadUnknownPlatformSizeLimit = const GiB(2).size;
final publicDownloadWebSizeLimit = const MiB(500).size;
final publicDownloadFirefoxSizeLimit = const GiB(2).size;
final publicDownloadMobileSizeLimit = const MiB(300).size;

final privateDownloadUnknownPlatformSizeLimit = const GiB(2).size;
final privateDownloadWebSizeLimit = const MiB(500).size;
final privateDownloadFirefoxSizeLimit = const GiB(2).size;
final privateDownloadMobileSizeLimit = const MiB(300).size;

Future<int> calcDownloadSizeLimit(bool isPublic,
    {DeviceInfoPlugin? deviceInfo}) async {
  if (AppPlatform.getPlatform() == SystemPlatform.Web) {
    return await _webDownloadLimit(isPublic, deviceInfo);
  } else if (AppPlatform.isMobile) {
    return _mobileLimit(isPublic);
  } else {
    return _unknownPlatformLimit(isPublic);
  }
}

Future<int> _webDownloadLimit(
    bool isPublic, DeviceInfoPlugin? deviceInfo) async {
  if (isPublic) {
    return await AppPlatform.isFireFox(deviceInfo: deviceInfo)
        ? publicDownloadFirefoxSizeLimit
        : publicDownloadWebSizeLimit;
  }

  return await AppPlatform.isFireFox(deviceInfo: deviceInfo)
      ? privateDownloadFirefoxSizeLimit
      : privateDownloadWebSizeLimit;
}

int _mobileLimit(bool isPublic) {
  return isPublic
      ? publicDownloadMobileSizeLimit
      : privateDownloadMobileSizeLimit;
}

int _unknownPlatformLimit(bool isPublic) {
  return isPublic
      ? publicDownloadUnknownPlatformSizeLimit
      : privateDownloadUnknownPlatformSizeLimit;
}

// TODO: extend to work drives and folders
Future<bool> isSizeAboveDownloadSizeLimit(
    List<MultiDownloadItem> items, bool isPublic,
    {DeviceInfoPlugin? deviceInfo}) async {
  final totalSize = items
      .map((e) => e is MultiDownloadFile ? e.size : 0)
      .reduce((a, b) => a + b);

  final sizeLimit =
      await calcDownloadSizeLimit(isPublic, deviceInfo: deviceInfo);

  return totalSize > sizeLimit;
}
