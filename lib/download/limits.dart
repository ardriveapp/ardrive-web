// ignore: depend_on_referenced_packages
import 'package:device_info_plus/device_info_plus.dart';

import 'download_policy.dart';
import 'download_utils.dart';

/// The ceilings themselves now live next to the rules that apply them, in
/// [DownloadPolicy]. They are re-exported here because the download cubits and
/// the multi-download bloc still import them from this path.
export 'download_policy.dart'
    show
        publicDownloadUnknownPlatformSizeLimit,
        publicDownloadWebSizeLimit,
        publicDownloadFirefoxSizeLimit,
        publicDownloadSafariSizeLimit,
        publicDownloadMobileSizeLimit,
        privateDownloadUnknownPlatformSizeLimit,
        privateDownloadWebSizeLimit,
        privateDownloadFirefoxSizeLimit,
        privateDownloadMobileSizeLimit;

/// The multi-file (zip) download ceiling.
///
/// Kept as a free function because the multi-download bloc and its tests call
/// it; it is now a thin front for [DownloadPolicy.bundleLimit], which is the
/// only place that decides.
Future<int> calcDownloadSizeLimit(bool isPublic,
    {DeviceInfoPlugin? deviceInfo}) async {
  final limit =
      await DownloadPolicy(deviceInfo: deviceInfo).bundleLimit(isPublic: isPublic);

  // `bundleLimit` encodes a number for every platform.
  return limit.maxBytes!;
}

// TODO: extend to work drives and folders
Future<bool> isSizeAboveDownloadSizeLimit(
    List<MultiDownloadItem> items, bool isPublic,
    {DeviceInfoPlugin? deviceInfo}) async {
  final totalSize = items
      .map((e) => e is MultiDownloadFile ? e.size : 0)
      .reduce((a, b) => a + b);

  final limit =
      await DownloadPolicy(deviceInfo: deviceInfo).bundleLimit(isPublic: isPublic);

  return limit.isExceededBy(totalSize);
}
