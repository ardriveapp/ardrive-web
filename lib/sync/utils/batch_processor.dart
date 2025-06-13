import 'dart:math';

class BatchProcessor {
  Stream<double> batchProcess<T>({
    required List<T> list,
    required Stream<double> Function(List<T> items) endOfBatchCallback,
    required int batchSize,
  }) async* {
    if (batchSize <= 0) {
      throw ArgumentError('Batch size cannot be 0');
    }

    if (list.isEmpty) {
      return;
    }

    final length = list.length;

    for (var i = 0; i < (length / batchSize).ceil(); i++) {
      // Ensure the loop covers all items
      final currentBatch = <T>[];

      for (var j = i * batchSize; j < min(length, (i + 1) * batchSize); j++) {
        currentBatch.add(list[j]);
      }

      yield* endOfBatchCallback(currentBatch);
    }

    list.clear();
  }

  Stream<double> batchProcessStream<T>({
    required Stream<T> stream,
    required Stream<double> Function(List<T> items) endOfBatchCallback,
    required int batchSize,
  }) async* {
    if (batchSize <= 0) {
      throw ArgumentError('Batch size cannot be 0');
    }

    final buffer = <T>[];
    await for (final item in stream) {
      buffer.add(item);
      if (buffer.length >= batchSize) {
        yield* endOfBatchCallback(List<T>.from(buffer));
        buffer.clear();
      }
    }

    if (buffer.isNotEmpty) {
      yield* endOfBatchCallback(List<T>.from(buffer));
    }
  }
}
