import 'dart:async';
import 'dart:ui';

class Debouncer {
  final Duration delay;
  Timer? _timer;
  Completer? _completer;

  Debouncer({
    this.delay = const Duration(milliseconds: 500),
  });

  Future<void> run(VoidCallback action) {
    _timer?.cancel();
    _completer?.completeError('Cancelled');
    _completer = Completer();
    _timer = Timer(delay, () {
      _completer?.complete();
      _completer = null;
      action();
    });
    return _completer!.future;
  }
}
