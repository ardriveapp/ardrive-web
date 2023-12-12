import 'dart:async';

class Debouncer {
  final Duration delay;
  Timer? _timer;
  Completer? _completer;

  Debouncer({
    this.delay = const Duration(milliseconds: 500),
  });

  Future<void> run(Future Function() action) {
    _timer?.cancel();
    _completer?.completeError('Cancelled');
    _completer = Completer();
    _timer = Timer(delay, () {
      action().whenComplete(() {
        _completer?.complete();
        _completer = null;
      });
    });
    return _completer!.future;
  }
}
