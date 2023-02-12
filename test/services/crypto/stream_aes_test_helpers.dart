import 'dart:math';
import 'dart:typed_data';

Uint8List sequentialBytes(int length) {
  return Uint8List.fromList(List.generate(length, (n) => n % 256));
}

Stream<Uint8List> bufferToStream(Uint8List buffer, {int chunkSize=10}) async* {
  for (var i = 0; i < buffer.length; i += chunkSize) {
    yield buffer.sublist(i, min(i + chunkSize, buffer.length));
  }
}
