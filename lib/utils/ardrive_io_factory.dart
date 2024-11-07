import 'package:ardrive/utils/ardrive_io_integration_test.dart';
import 'package:ardrive_io/ardrive_io.dart';

class ArDriveIOFactory {
  // TODO: add constant for integration test environment variable
  static ArDriveIO createArDriveIO() {
    const isFromIntegrationTest = String.fromEnvironment('integration-test');

    if (isFromIntegrationTest == 'true') {
      return ArDriveIOIntegrationTest();
    }

    return ArDriveIO();
  }
}
