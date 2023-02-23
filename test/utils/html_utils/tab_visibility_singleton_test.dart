import 'package:ardrive/utils/html/html_util.dart';
import 'package:flutter_test/flutter_test.dart';

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
