import 'package:ardrive/sync/utils/batch_processor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockEndOfBatchCallback<T> extends Mock {
  Stream<double> call(List<T> items);
}

void main() {
  group('BatchProcessor', () {
    late MockEndOfBatchCallback<int> mockCallback;

    setUp(() {
      mockCallback = MockEndOfBatchCallback<int>();
      // Set up mock callback behavior
      when(() => mockCallback(any())).thenAnswer((invocation) async* {
        yield 1.0; // Simulate processing the batch
      });
    });

    test('should produce no output for an empty list', () {
      final processor = BatchProcessor();
      expect(
          processor.batchProcess<int>(
              list: [], endOfBatchCallback: mockCallback.call, batchSize: 5),
          emitsDone);
    });

    test('should handle batch size larger than list', () {
      final processor = BatchProcessor();
      final list = [1, 2, 3];
      const batchSize = 10;
      expect(
          processor.batchProcess<int>(
              list: list,
              endOfBatchCallback: mockCallback.call,
              batchSize: batchSize),
          emitsInOrder([1.0, emitsDone]));
    });

    test(
        'should split list into multiple smaller lists when batch size is smaller than list',
        () {
      final processor = BatchProcessor();
      final list = List.generate(10, (index) => index); // List from 0 to 9
      const batchSize = 2;
      // Expect 5 batches if batch size is 2
      expect(
          processor.batchProcess<int>(
              list: list,
              endOfBatchCallback: mockCallback.call,
              batchSize: batchSize),
          emitsInOrder([1.0, 1.0, 1.0, 1.0, 1.0, emitsDone]));
    });

    test('should handle list size exactly divisible by batch size', () {
      final processor = BatchProcessor();
      final list = List.generate(10, (index) => index); // List from 0 to 9
      const batchSize = 5;
      // Expect 2 batches if batch size is 5
      expect(
          processor.batchProcess<int>(
              list: list,
              endOfBatchCallback: mockCallback.call,
              batchSize: batchSize),
          emitsInOrder([1.0, 1.0, emitsDone]));
    });

    test('should handle list size not exactly divisible by batch size', () {
      final processor = BatchProcessor();
      final list = List.generate(11, (index) => index); // List from 0 to 10
      const batchSize = 5;
      // Expect 3 batches if batch size is 5, because the last batch will have only one element
      expect(
          processor.batchProcess<int>(
              list: list,
              endOfBatchCallback: mockCallback.call,
              batchSize: batchSize),
          emitsInOrder([1.0, 1.0, 1.0, emitsDone]));
    });

    test('should throw exception for invalid batch size', () async {
      final processor = BatchProcessor();
      final list = [1, 2, 3];
      const batchSize = 0; // Invalid batch size

      expect(
        processor.batchProcess<int>(
            list: list,
            endOfBatchCallback: mockCallback.call,
            batchSize: batchSize),
        emitsError(
          isA<ArgumentError>(),
        ),
      );
    });
  });
}
