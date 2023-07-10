import 'dart:typed_data';

import 'package:ardrive/utils/data_item_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockDataItem extends Mock implements DataItem {}

void main() {
  group('convertDataItemToStreamBytes', () {
    late DataItem dataItem;

    setUp(() {
      dataItem = MockDataItem();
    });

    test('should convert DataItem to Stream<List<int>> of bytes', () async {
      final byteList = Uint8List.fromList([1, 2, 3]);
      final expectedList = [
        [1, 2, 3]
      ];

      when(() => dataItem.asBinary())
          .thenAnswer((_) async => BytesBuilder()..add(byteList));
      final result = await convertDataItemToStreamBytes(dataItem);

      expect(await result.toList(), equals(expectedList));
    });
  });
}
