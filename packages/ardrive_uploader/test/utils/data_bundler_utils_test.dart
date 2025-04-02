import 'package:ardrive_uploader/src/utils/data_bundler_utils.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/foundation.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../metadata_generator_test.dart';

class MockAppInfo extends Mock implements AppInfo {}

void main() {
  late MockAppInfoServices mockAppInfoServices;
  late MockAppInfo mockAppInfo;

  setUp(() {
    mockAppInfoServices = MockAppInfoServices();
    mockAppInfo = MockAppInfo();

    when(() => mockAppInfo.version).thenReturn('1.0.0');
    when(() => mockAppInfo.platform).thenReturn('Android');
    when(() => mockAppInfo.appName).thenReturn('ArDrive-App');
    when(() => mockAppInfoServices.appInfo).thenReturn(mockAppInfo);
    when(() => mockAppInfo.arfsVersion).thenReturn('0.15');
  });

  test(
      'returns tags from appTags and a hardcoded tag when customBundleTags is null',
      () {
    final result = getBundleTags(mockAppInfoServices, null);

    expect(
        result,
        containsAll([
          Tag(EntityTag.appName, 'ArDrive-App'),
          Tag(EntityTag.appPlatform, 'Android'),
          Tag(EntityTag.appVersion, '1.0.0'),
          isA<Tag>().having((t) => t.name, 'tag name', EntityTag.unixTime),
          Tag(EntityTag.tipType, 'data upload'),
        ]));

    debugPrint(getJsonFromListOfTags(result));
  });

  test(
      'returns tags from appTags, a hardcoded tag, and customBundleTags when customBundleTags is not null',
      () {
    final customTags = [
      Tag('custom-tag-1', 'customTag1'),
      Tag('custom-tag-2', 'customTag2')
    ];

    final result = getBundleTags(mockAppInfoServices, customTags);

    expect(
        result,
        containsAll([
          Tag(EntityTag.appName, 'ArDrive-App'),
          Tag(EntityTag.appPlatform, 'Android'),
          Tag(EntityTag.appVersion, '1.0.0'),
          isA<Tag>().having((t) => t.name, 'tag name', EntityTag.unixTime),
          Tag(EntityTag.tipType, 'data upload'),
          ...customTags,
        ]));

    debugPrint(getJsonFromListOfTags(result));
  });
}
