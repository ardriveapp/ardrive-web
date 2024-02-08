import 'package:ardrive/utils/debouncer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Debouncer class', () {
    test('should run action after delay', () async {
      final debouncer = Debouncer(delay: const Duration(milliseconds: 100));
      var run = false;
      debouncer.run(() async {
        run = true;
      });
      expect(run, false);
      await Future.delayed(const Duration(milliseconds: 200));
      expect(run, true);
    });

    test('should cancel action', () async {
      final debouncer = Debouncer(delay: const Duration(milliseconds: 100));
      var run = false;
      debouncer.run(() async {
        run = true;
      }).catchError((e) {
        expect(e, 'Cancelled');
      });
      expect(run, false);
      debouncer.cancel();
      await Future.delayed(const Duration(milliseconds: 200));
      expect(run, false);
    });

    test('should run only last action', () async {
      final debouncer = Debouncer(delay: const Duration(milliseconds: 100));
      var run = false;
      debouncer.run(() async {
        run = true;
      }).catchError((e) {
        expect(e, 'Cancelled');
      });
      debouncer.run(() async {
        run = false;
      }).catchError((e) {
        expect(e, 'Cancelled');
      });
      await Future.delayed(const Duration(milliseconds: 200));
      expect(run, false);
    });
  });
}
