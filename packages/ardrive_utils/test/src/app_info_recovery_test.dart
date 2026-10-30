import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The start loads the version without waiting, and only once. If
  // version.json could not be read then, [AppInfoServices.appInfo] threw on
  // every upload, licence and migration until a reload. [getAppInfo] is what
  // they read now: it loads again.
  test('getAppInfo recovers from a failed load at the start', () async {
    final services = AppInfoServices();

    await expectLater(services.loadAppInfo(), throwsA(anything));
    expect(() => services.appInfo, throwsStateError);

    PackageInfo.setMockInitialValues(
      appName: 'ArDrive',
      packageName: 'ardrive',
      version: '2.90.0',
      buildNumber: '1',
      buildSignature: '',
    );

    final info = await services.getAppInfo();
    expect(info.version, '2.90.0');
    expect(services.appInfo.version, '2.90.0');
  });
}
