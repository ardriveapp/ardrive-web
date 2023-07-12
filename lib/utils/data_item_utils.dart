import 'package:arweave/arweave.dart';
import 'package:flutter/foundation.dart';

/// Converts a [DataItem] to a [Stream<List<int>>] of bytes.
Future<Stream<List<int>>> convertDataItemToStreamBytes(
    DataItem dataItem) async {
  Uint8List byteList = (await dataItem.asBinary()).toBytes();

  Stream<List<int>> stream = Stream.fromIterable([byteList]);

  return stream;
}
