import 'package:ardrive/main.dart' as app;
import 'package:ardrive/services/pst/pst.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    app.main();
  });
  group('pst service test', () {
    test('pst service fetches a non zero pst fee', () async {
      expect(await PstService().getPstFeePercentage(), isNonZero);
    });
    test('pst service fetches a pst ', () async {
      expect(await PstService().getWeightedPstHolder(), isNotEmpty);
    });
  });
}
