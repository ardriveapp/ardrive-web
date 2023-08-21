import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/utils/data_size.dart';
import 'package:device_info_plus/device_info_plus.dart';

import '../utils/app_platform.dart';

final publicDownloadDesktopSizeLimit = const GiB(2).size;
final publicDownloadWebSizeLimit = const MiB(500).size;
final publicDownloadFirefoxSizeLimit = const GiB(2).size;
final publicDownloadMobileSizeLimit = const MiB(300).size;

// unlimited size, use 1000 GiB as a limit
final privateDownloadDesktopSizeLimit = const GiB(2000).size;
final privateDownloadWebSizeLimit = const MiB(500).size;
final privateDownloadFirefoxSizeLimit = const GiB(2).size;
final privateDownloadMobileSizeLimit = const MiB(300).size;

Future<int> calcDownloadSizeLimit(bool isPublic) async {
  final info = await DeviceInfoPlugin().deviceInfo;
  final isFirefox =
      info is WebBrowserInfo && info.browserName == BrowserName.firefox;

  if (isPublic) {
    if (AppPlatform.isMobile) {
      return publicDownloadWebSizeLimit;
    } else if (AppPlatform.getPlatform() == SystemPlatform.Web) {
      return isFirefox
          ? publicDownloadFirefoxSizeLimit
          : publicDownloadWebSizeLimit;
    } else {
      return publicDownloadDesktopSizeLimit;
    }
  } else {
    if (AppPlatform.isMobile) {
      return privateDownloadWebSizeLimit;
    } else if (AppPlatform.getPlatform() == SystemPlatform.Web) {
      return isFirefox
          ? privateDownloadFirefoxSizeLimit
          : privateDownloadWebSizeLimit;
    } else {
      return privateDownloadDesktopSizeLimit;
    }
  }
}

// TODO: extend to work drives and folders
Future<bool> isSizeAboveDownloadSizeLimit(
    List<ARFSFileEntity> items, bool isPublic) async {
  final totalSize = items.map((e) => e.size).reduce((a, b) => a + b);

  final sizeLimit = await calcDownloadSizeLimit(isPublic);

  return totalSize > sizeLimit;
}
