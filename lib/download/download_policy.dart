import 'package:ardrive_uploader/ardrive_uploader.dart'
    show maxSizeSupportedByGCMEncryption;
import 'package:ardrive_utils/ardrive_utils.dart';
// ignore: depend_on_referenced_packages
import 'package:device_info_plus/device_info_plus.dart';

/// Ceilings, as they are encoded today.
///
/// These numbers are *not* measurements of what each browser can actually save
/// — they are the conservative gates the app has always shipped. Raising any of
/// them waits on per-browser validation of the streaming save path (redesign
/// plan §3.5), so [DownloadPolicy] only rationalises *where* they are applied,
/// never *how large* they are.
final publicDownloadUnknownPlatformSizeLimit = const GiB(2).size;
final publicDownloadWebSizeLimit = const MiB(500).size;
final publicDownloadFirefoxSizeLimit = const GiB(2).size;

/// Safari's single-file ceiling.
///
/// [DownloadPolicy.singleFileLimit] is the one place that reads this value
/// (F22): both download cubits ask the policy rather than comparing against
/// the constant themselves, so there is one rule to change and one rule to
/// test.
final publicDownloadSafariSizeLimit = const GiB(1).size;
final publicDownloadMobileSizeLimit = const MiB(300).size;

final privateDownloadUnknownPlatformSizeLimit = const GiB(2).size;
final privateDownloadWebSizeLimit = const MiB(500).size;
final privateDownloadFirefoxSizeLimit = const GiB(2).size;
final privateDownloadMobileSizeLimit = const MiB(300).size;

/// Which rule produced a [DownloadSizeLimit].
///
/// Carried alongside the number so the UI can name it — "Firefox supports up
/// to 2 GB" only makes sense when you know the current ceiling came from the
/// generic web rule and not from Firefox's.
enum DownloadSizeLimitSource {
  safari,
  firefox,
  web,
  mobile,
  unknownPlatform,

  /// No ceiling is encoded for this platform and flow. This is a statement
  /// about the code, not a promise that any size will work.
  none,
}

/// A ceiling and where it came from.
class DownloadSizeLimit {
  const DownloadSizeLimit(this.maxBytes, this.source);

  const DownloadSizeLimit.none()
      : maxBytes = null,
        source = DownloadSizeLimitSource.none;

  /// `null` when no ceiling is encoded for this platform and flow.
  final int? maxBytes;

  final DownloadSizeLimitSource source;

  /// Matches the comparison the call sites have always used: a file exactly on
  /// the limit is allowed, one byte over is not.
  bool allows(int sizeBytes) {
    final max = maxBytes;
    return max == null || sizeBytes <= max;
  }

  bool isExceededBy(int sizeBytes) => !allows(sizeBytes);

  @override
  String toString() => 'DownloadSizeLimit(${maxBytes ?? 'none'}, ${source.name})';
}

/// Every size gate on the download path, in one place.
///
/// Before this existed the gates were spread over three files and disagreed
/// with each other: `calcDownloadSizeLimit` knew about Firefox but not Safari,
/// while the single-file cubits knew about Safari and nothing else (F22, and
/// redesign plan §0.5/§3.3). The disagreement is preserved here deliberately —
/// the two flows really do have different ceilings — but it is now written
/// down in one place and can be tested.
///
/// Nothing here raises a ceiling. [singleFileLimit] and [bundleLimit] return
/// what the corresponding call sites enforce, with one deliberate
/// consequence of putting the rule in one place: a shared-link download on a
/// phone is now held to the same private-file ceiling a personal one has
/// always been held to, instead of being the one flow with no ceiling at all.
class DownloadPolicy {
  const DownloadPolicy({DeviceInfoPlugin? deviceInfo})
      : _deviceInfo = deviceInfo;

  final DeviceInfoPlugin? _deviceInfo;

  /// The largest ciphertext the buffered, MAC-verified AES-GCM download path
  /// will hold in memory.
  ///
  /// This is not a policy choice so much as a fact about the uploader: it
  /// picks AES-GCM only below [maxSizeSupportedByGCMEncryption] and AES-CTR at
  /// or above it, so a GCM file is bounded by construction. The downloader
  /// still checks, because "bounded by construction" is only true as long as
  /// the two constants agree.
  static final int maxBufferedCiphertextBytes = maxSizeSupportedByGCMEncryption;

  /// The ceiling for one file saved straight to disk.
  ///
  /// Safari is the only browser with a ceiling here, and this is the single
  /// call site of [publicDownloadSafariSizeLimit]. Every other browser is
  /// ungated for single files today; that is reported honestly as
  /// [DownloadSizeLimitSource.none] rather than by inventing a number, because
  /// inventing one would *lower* a ceiling users rely on.
  Future<DownloadSizeLimit> singleFileLimit({required bool isPublic}) async {
    switch (AppPlatform.getPlatform()) {
      case SystemPlatform.Web:
        if (await AppPlatform.isSafari(deviceInfo: _deviceInfo)) {
          return DownloadSizeLimit(
            publicDownloadSafariSizeLimit,
            DownloadSizeLimitSource.safari,
          );
        }
        return const DownloadSizeLimit.none();
      case SystemPlatform.Android:
      case SystemPlatform.iOS:
        // Only private downloads are gated on mobile today; public ones go
        // through the platform downloader, which has no such check.
        return isPublic
            ? const DownloadSizeLimit.none()
            : DownloadSizeLimit(
                privateDownloadMobileSizeLimit,
                DownloadSizeLimitSource.mobile,
              );
      case SystemPlatform.Windows:
      case SystemPlatform.unknown:
        return const DownloadSizeLimit.none();
    }
  }

  /// The ceiling for a multi-file download, which is zipped in the browser
  /// before anything is saved.
  ///
  /// [DownloadSizeLimit.maxBytes] is never `null` here — every platform has a
  /// number. Safari deliberately gets the plain web ceiling, not
  /// [publicDownloadSafariSizeLimit]: 500 MiB is what it enforces today and
  /// this change is not allowed to raise it.
  Future<DownloadSizeLimit> bundleLimit({required bool isPublic}) async {
    switch (AppPlatform.getPlatform()) {
      case SystemPlatform.Web:
        if (await AppPlatform.isFireFox(deviceInfo: _deviceInfo)) {
          return DownloadSizeLimit(
            isPublic
                ? publicDownloadFirefoxSizeLimit
                : privateDownloadFirefoxSizeLimit,
            DownloadSizeLimitSource.firefox,
          );
        }
        return DownloadSizeLimit(
          isPublic ? publicDownloadWebSizeLimit : privateDownloadWebSizeLimit,
          DownloadSizeLimitSource.web,
        );
      case SystemPlatform.Android:
      case SystemPlatform.iOS:
        return DownloadSizeLimit(
          isPublic
              ? publicDownloadMobileSizeLimit
              : privateDownloadMobileSizeLimit,
          DownloadSizeLimitSource.mobile,
        );
      case SystemPlatform.Windows:
      case SystemPlatform.unknown:
        return DownloadSizeLimit(
          isPublic
              ? publicDownloadUnknownPlatformSizeLimit
              : privateDownloadUnknownPlatformSizeLimit,
          DownloadSizeLimitSource.unknownPlatform,
        );
    }
  }
}
