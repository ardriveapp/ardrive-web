import 'package:ardrive/main.dart' as app;
import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/services/pst/pst.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    app.main();
  });
  group('service test', () {
    test(
        'arconnect service isExtension present function returns false when arconnect is not present',
        () {
      expect(ArConnectService().isExtensionPresent(), isFalse);
    });
    test('pst service fetches current pst fee', () async {
      expect(await PstService().getPstFeePercentage(), isNonZero);
    });
  });
}
