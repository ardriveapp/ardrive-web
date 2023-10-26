import 'dart:typed_data';

Future<Uint8List> streamToUint8List(Stream<Uint8List> stream) async {
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
