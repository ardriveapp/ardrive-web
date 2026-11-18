import 'package:ardrive/download/download_policy.dart';
import 'package:ardrive/download/limits.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
// ignore: depend_on_referenced_packages
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/mocks.dart';

void main() {
  late MockDeviceInfoPlugin deviceInfo;

  setUp(() {
    deviceInfo = MockDeviceInfoPlugin();
  });

  void stubBrowser(String userAgent) {
    when(() => deviceInfo.deviceInfo).thenAnswer(
      (_) async => WebBrowserInfo.fromMap({'userAgent': userAgent}),
    );
  }

  void browser(String userAgent) {
    AppPlatform.setMockPlatform(platform: SystemPlatform.Web);
    stubBrowser(userAgent);
  }

  DownloadPolicy policy() => DownloadPolicy(deviceInfo: deviceInfo);

  group('single file ceilings', () {
    test('Safari is the one browser with a single-file ceiling, and it is the '
        'declared 1 GiB', () async {
      browser('Safari');

      final publicLimit = await policy().singleFileLimit(isPublic: true);
      final privateLimit = await policy().singleFileLimit(isPublic: false);

      expect(publicLimit.maxBytes, publicDownloadSafariSizeLimit);
      expect(publicLimit.source, DownloadSizeLimitSource.safari);
      expect(privateLimit.maxBytes, publicDownloadSafariSizeLimit);

      // The comparison the call sites make: exactly on the limit is fine.
      expect(publicLimit.allows(publicDownloadSafariSizeLimit), isTrue);
      expect(publicLimit.isExceededBy(publicDownloadSafariSizeLimit), isFalse);
      expect(publicLimit.isExceededBy(publicDownloadSafariSizeLimit + 1), isTrue);
    });

    test('other browsers have no single-file ceiling, which is reported as '
        'none rather than invented', () async {
      for (final userAgent in ['Chrome', 'Firefox', 'Edg']) {
        browser(userAgent);

        final limit = await policy().singleFileLimit(isPublic: true);

        expect(limit.maxBytes, isNull, reason: userAgent);
        expect(limit.source, DownloadSizeLimitSource.none, reason: userAgent);
        // Not gated means not gated - it must not silently inherit the bundle
        // ceiling, which would lower what users can download today.
        expect(limit.allows(publicDownloadWebSizeLimit * 10), isTrue,
            reason: userAgent);
      }
    });

    test('mobile gates private single files at the mobile limit and leaves '
        'public ones to the platform downloader', () async {
      for (final platform in [SystemPlatform.Android, SystemPlatform.iOS]) {
        AppPlatform.setMockPlatform(platform: platform);

        final private = await policy().singleFileLimit(isPublic: false);
        final public = await policy().singleFileLimit(isPublic: true);

        expect(private.maxBytes, privateDownloadMobileSizeLimit);
        expect(private.source, DownloadSizeLimitSource.mobile);
        expect(public.maxBytes, isNull);
      }
    });

    test('unknown platforms have no single-file ceiling', () async {
      AppPlatform.setMockPlatform(platform: SystemPlatform.unknown);

      expect((await policy().singleFileLimit(isPublic: true)).maxBytes, isNull);
      expect((await policy().singleFileLimit(isPublic: false)).maxBytes, isNull);
    });
  });

  group('bundle (multi-file zip) ceilings', () {
    test('web keeps 500 MiB', () async {
      browser('Chrome');

      expect((await policy().bundleLimit(isPublic: true)).maxBytes,
          publicDownloadWebSizeLimit);
      expect((await policy().bundleLimit(isPublic: false)).maxBytes,
          privateDownloadWebSizeLimit);
      expect((await policy().bundleLimit(isPublic: true)).source,
          DownloadSizeLimitSource.web);
    });

    test('Firefox keeps 2 GiB', () async {
      browser('Firefox');

      expect((await policy().bundleLimit(isPublic: true)).maxBytes,
          publicDownloadFirefoxSizeLimit);
      expect((await policy().bundleLimit(isPublic: false)).maxBytes,
          privateDownloadFirefoxSizeLimit);
      expect((await policy().bundleLimit(isPublic: true)).source,
          DownloadSizeLimitSource.firefox);
    });

    test('Safari keeps the plain web ceiling - consolidating the gates must '
        'not raise it to the 1 GiB single-file number', () async {
      browser('Safari');

      final limit = await policy().bundleLimit(isPublic: true);

      expect(limit.maxBytes, publicDownloadWebSizeLimit);
      expect(limit.maxBytes, lessThan(publicDownloadSafariSizeLimit));
      expect(limit.source, DownloadSizeLimitSource.web);
    });

    test('mobile keeps 300 MiB and unknown platforms keep 2 GiB', () async {
      AppPlatform.setMockPlatform(platform: SystemPlatform.Android);
      expect((await policy().bundleLimit(isPublic: true)).maxBytes,
          publicDownloadMobileSizeLimit);
      expect((await policy().bundleLimit(isPublic: false)).maxBytes,
          privateDownloadMobileSizeLimit);

      AppPlatform.setMockPlatform(platform: SystemPlatform.unknown);
      expect((await policy().bundleLimit(isPublic: true)).maxBytes,
          publicDownloadUnknownPlatformSizeLimit);
      expect((await policy().bundleLimit(isPublic: false)).maxBytes,
          privateDownloadUnknownPlatformSizeLimit);
    });

    test('every platform encodes a bundle ceiling', () async {
      stubBrowser('Chrome');

      for (final platform in SystemPlatform.values) {
        AppPlatform.setMockPlatform(platform: platform);

        expect((await policy().bundleLimit(isPublic: true)).maxBytes, isNotNull,
            reason: platform.name);
        expect((await policy().bundleLimit(isPublic: false)).maxBytes, isNotNull,
            reason: platform.name);
      }
    });
  });

  group('calcDownloadSizeLimit still answers what it always did', () {
    test('it is the bundle ceiling, Safari included', () async {
      browser('Safari');

      expect(await calcDownloadSizeLimit(true, deviceInfo: deviceInfo),
          publicDownloadWebSizeLimit);

      browser('Firefox');

      expect(await calcDownloadSizeLimit(false, deviceInfo: deviceInfo),
          privateDownloadFirefoxSizeLimit);
    });
  });

  test('the buffered AES-GCM ceiling matches the cipher the uploader picks',
      () {
    // Anything the uploader encrypts with AES-GCM is below this, so the
    // buffered, MAC-verified download path is bounded by construction.
    expect(DownloadPolicy.maxBufferedCiphertextBytes, const MiB(100).size);
  });
}
