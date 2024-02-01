import 'dart:async';
import 'dart:typed_data';

/// Concatenates a stream of `Uint8List` elements into a single `Uint8List`.
///
/// This method takes a `Stream<Uint8List>` as input and concatenates all the
/// `Uint8List` elements from the stream into one continuous `Uint8List`. It is
/// useful for combining multiple binary data chunks into a single data array.
///
/// The method waits for all elements of the stream to be collected before
/// performing the concatenation. If the stream emits an error, the method will
/// propagate this error.
///
/// Example:
///
/// ```dart
/// Stream<Uint8List> stream = Stream.fromIterable([
///   Uint8List.fromList([1, 2]),
///   Uint8List.fromList([3, 4]),
/// ]);
/// Uint8List result = await concatenateUint8ListStream(stream);
/// // result will be Uint8List [1, 2, 3, 4]
/// ```
Future<Uint8List> concatenateUint8ListStream(Stream<Uint8List> stream) async {
  List<Uint8List> collectedData = await stream.toList();
  int totalLength =
      collectedData.fold(0, (prev, element) => prev + element.length);

  final result = Uint8List(totalLength);
  int offset = 0;

  for (var data in collectedData) {
    result.setRange(offset, offset + data.length, data);
    offset += data.length;
  }

  return result;
}

final StreamTransformer<List<int>, Uint8List> listIntToUint8ListTransformer =
    StreamTransformer.fromHandlers(
  handleData: (List<int> data, EventSink<Uint8List> sink) {
    sink.add(Uint8List.fromList(data));
  },
);
