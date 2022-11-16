import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/utils/app_platform.dart';
import 'package:ardrive/utils/bundles/fake_tags.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:test/test.dart';

import '../test_utils/fake_data.dart';

void main() {
  PackageInfo.setMockInitialValues(
    appName: appName,
    packageName: packageName,
    version: version,
    buildNumber: buildNumber,
    buildSignature: buildSignature,
  );
  late PackageInfo packageInfo;

  group('fakeApplicationTags method', () {
    setUp(() async {
      packageInfo = await PackageInfo.fromPlatform();
    });

    test('contains the expected tags', () async {
      AppPlatform.setMockPlatform(platform: SystemPlatform.Android);

      final tags = fakeApplicationTags(
        version: version,
      );

      expect(
        tags[0].name,
        EntityTag.appName,
      );
      expect(
        tags[0].value,
        appName,
      );

      expect(
        tags[1].name,
        EntityTag.appVersion,
      );
      expect(
        tags[1].value,
        version,
      );

      expect(
        tags[2].name,
        EntityTag.unixTime,
      );
      expect(
        tags[2].value,
        isA<String>(),
      );

      expect(
        tags[3].name,
        EntityTag.appPlatform,
      );
      expect(
        tags[3].value,
        'Android',
      );
    });

    test('contains the expected tags', () async {
      AppPlatform.setMockPlatform(platform: SystemPlatform.iOS);

      final tags = fakeApplicationTags(
        version: version,
      );

      expect(
        tags[0].name,
        EntityTag.appName,
      );
      expect(
        tags[0].value,
        appName,
      );

      expect(
        tags[1].name,
        EntityTag.appVersion,
      );
      expect(
        tags[1].value,
        version,
      );

      expect(
        tags[2].name,
        EntityTag.unixTime,
      );
      expect(
        tags[2].value,
        isA<String>(),
      );

      expect(
        tags[3].name,
        EntityTag.appPlatform,
      );
      expect(
        tags[3].value,
        'iOS',
      );
    });
    test('contains the expected tags', () async {
      AppPlatform.setMockPlatform(platform: SystemPlatform.Web);

      final tags = fakeApplicationTags(
        version: version,
      );

      expect(
        tags[0].name,
        EntityTag.appName,
      );
      expect(
        tags[0].value,
        appName,
      );

      expect(
        tags[1].name,
        EntityTag.appVersion,
      );
      expect(
        tags[1].value,
        version,
      );

      expect(
        tags[2].name,
        EntityTag.unixTime,
      );
      expect(
        tags[2].value,
        isA<String>(),
      );

      expect(
        tags[3].name,
        EntityTag.appPlatform,
      );
      expect(
        tags[3].value,
        'Web',
      );
    });
  });
}
