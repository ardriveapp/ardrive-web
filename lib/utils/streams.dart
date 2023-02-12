import 'dart:async';
import 'dart:typed_data';

StreamTransformer<Uint8List, Uint8List> trimData(int byteCount) {
  var complete = false;
  var processedBytes = 0;
  return StreamTransformer.fromHandlers(
    handleData: (data, sink) {
      if (complete) return;
      if (processedBytes + data.length >= byteCount) {
        sink.add(Uint8List.sublistView(data, 0, byteCount - processedBytes));
        sink.close();
        complete = true;
      } else {
        sink.add(data);
        processedBytes += data.length;
      }
    },
  );
}
