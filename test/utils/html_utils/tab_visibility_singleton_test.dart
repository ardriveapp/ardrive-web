import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter_test/flutter_test.dart';

// TODO: move this test for TabVisibilitySingleton to ardrive_utils
void main() {
  group('TabVisibilitySingleton class', () {
    test(
      'as a singleton, reutns the same instance every time it\'s constructed',
      () {
        final tabVisibilitySingleton1 = TabVisibilitySingleton();
        final tabVisibilitySingleton2 = TabVisibilitySingleton();

        expect(tabVisibilitySingleton1, tabVisibilitySingleton2);
      },
    );
  });
}
