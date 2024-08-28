import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:ario_sdk/src/implementations/ario_sdk_web_stub.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ArioSDKFactory creates ArioSDKWeb for Web platform', () {
    // Arrange
    AppPlatform.setMockPlatform(platform: SystemPlatform.Web);

    // Act
    final sdk = ArioSDKFactory().create();

    // Assert
    expect(sdk, isA<ArioSDKWeb>());
  });

  test('ArioSDKFactory throws UnsupportedError for non-Web platforms', () {
    // Arrange
    AppPlatform.setMockPlatform(platform: SystemPlatform.Android);

    // Act & Assert
    expect(() => ArioSDKFactory().create(), throwsUnsupportedError);
  });
}
