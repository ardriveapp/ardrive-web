import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The app starts this load without waiting for it, so whatever needs the
  // version later calls it again: that call must join the load, not start
  // another fetch of version.json, and must try again after a failure.
  test('loads once, and again only after a failure', () async {
    final services = AppInfoServices();

    // No platform answer yet: the load fails.
    await expectLater(services.loadAppInfo(), throwsA(anything));
    expect(() => services.appInfo, throwsStateError);

    PackageInfo.setMockInitialValues(
      appName: 'ArDrive',
      packageName: 'ardrive',
      version: '1.2.3',
      buildNumber: '1',
      buildSignature: '',
    );
    final first = services.loadAppInfo();
    expect(identical(services.loadAppInfo(), first), isTrue);
    await first;
    expect(services.appInfo.version, '1.2.3');
  });
}
