/*
import 'dart:async';

class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer({required this.delay});

  void run(void Function() callback) {
    if (_timer != null) {
      _timer?.cancel();
    }
    _timer = Timer(delay, callback);
  }
}
*/

import 'package:ardrive/utils/debouncer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Debouncer class', () {
    const delay = Duration(milliseconds: 50);

    test('should run the callback after the delay', () async {
      final Debouncer debouncer = Debouncer(delay: delay);
      int counter = 0;
      debouncer.run(() {
        counter++;
      });
      expect(counter, 0);
      await Future<dynamic>.delayed(delay);
      expect(counter, 1);
    });

    test('should cancel the previous callback', () async {
      final Debouncer debouncer = Debouncer(delay: delay);
      int counter = 0;
      debouncer.run(() {
        counter++;
      });
      debouncer.run(() {
        counter++;
      });
      expect(counter, 0);
      await Future<dynamic>.delayed(delay);
      expect(counter, 1);
    });
  });
}
