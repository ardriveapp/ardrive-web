import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/utils/snapshots/snapshot_types.dart';

/// FIXME: this should be a stream transform, not a function

// Function that maps a stream of TxSnapshot to a stream of JSON serialized objects as Uint8Array
Stream<Uint8List> gqlEdgesToSnapshotDataStreamTransform(
    Stream<TxSnapshot> stream) async* {
  // Use a JSON encoder to serialize the objects in the stream.
  const encoder = JsonEncoder();

  // Yield the beginning of a JSON array
  yield Uint8List.fromList(utf8.encode('{"txSnapshots":['));

  int index = 0;

  // Iterate through the stream
  await for (final txSnapshot in stream) {
    // If this is not the first object in the stream, yield a comma separator
    if (index != 0) {
      yield Uint8List.fromList(utf8.encode(','));
    }

    // Update the index, so that future iterations know they are not the first object
    index++;

    // Serialize the object to a JSON string
    final jsonString = encoder.convert(txSnapshot);

    // Convert the JSON string to a Uint8Array.
    final jsonData = Uint8List.fromList(utf8.encode(jsonString));
    yield jsonData;
  }

  // Yield the end of the JSON array
  yield Uint8List.fromList(utf8.encode(']}'));
}
