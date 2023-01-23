import 'dart:collection';

class OpenStreamQueue<T> {
  late final Queue<Stream<T>> _queue;

  OpenStreamQueue(Stream<T> Function(int n) generator, int n) {
    _queue = Queue<Stream<T>>.from(List.generate(n, (n) => generator(n)));
  }

  Stream<T> pop() {
    if (_queue.isEmpty) {
      throw StateError('No more elements in the queue');
    }
    return _queue.removeFirst();
  }
}
