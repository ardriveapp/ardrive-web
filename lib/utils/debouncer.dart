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
