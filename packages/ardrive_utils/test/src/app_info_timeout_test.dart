import 'dart:async';

import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // package_info_plus fetches version.json with no timeout of its own. A
  // fetch that never answers must not leave an upload waiting for ever: the
  // load gives up, and the next one tries again.
  test('a version read that never answers times out and is tried again',
      () async {
    final services = AppInfoServices()
      ..loadTimeout = const Duration(milliseconds: 50)
      ..readPackageInfo = () => Completer<PackageInfo>().future;

    await expectLater(services.getAppInfo(), throwsA(isA<TimeoutException>()));

    services.readPackageInfo = () async => PackageInfo(
          appName: 'ArDrive',
          packageName: 'ardrive',
          version: '2.90.0',
          buildNumber: '1',
        );
    expect((await services.getAppInfo()).version, '2.90.0');
  });
}
