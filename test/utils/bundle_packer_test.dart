import 'package:ardrive/utils/bundles/next_fit_bundle_packer.dart';
import 'package:ardrive/utils/bundles/sized_item.dart';
import 'package:collection/collection.dart';
import 'package:test/test.dart';

class TestSizedItem implements SizedItem {
  @override
  int size;
  TestSizedItem({
    required this.size,
  });
}

void main() {
  group('NextFitBundlePacker Tests', () {
    group('packItems Function', () {
      test('Returns an empty bundles list when passed no items', () async {
        final binPacker =
            NextFitBundlePacker(maxBundleSize: 5, maxDataItemCount: 1);
        expect(await binPacker.packItems([]), isEmpty);
      });

      test('Throws an exception if item exceeds max packing size', () async {
        final binPacker =
            NextFitBundlePacker(maxBundleSize: 5, maxDataItemCount: 10);
        expect(
          () async => await binPacker.packItems([TestSizedItem(size: 6)]),
          throwsException,
        );
      });

      test('Creates a single bundle of max size for one max size item',
          () async {
        final testItem = TestSizedItem(size: 5);
        final binPacker =
            NextFitBundlePacker(maxBundleSize: 5, maxDataItemCount: 10);
        final actualResult = await binPacker.packItems([testItem]);
        final expectedResult = [
          [testItem]
        ];
        expect(
          const DeepCollectionEquality().equals(actualResult, expectedResult),
          true,
        );
      });

      test('Creates a new bundle when next item does not fit', () async {
        final testItem1 = TestSizedItem(size: 5);
        final testItem2 = TestSizedItem(size: 1);
        final binPacker =
            NextFitBundlePacker(maxBundleSize: 5, maxDataItemCount: 10);
        final actualResult = await binPacker.packItems([testItem1, testItem2]);
        final expectedResult = [
          [testItem1],
          [testItem2]
        ];
        printOnFailure(
            actualResult.map((e) => e.map((e) => e.size)).toString());
        expect(
          const DeepCollectionEquality().equals(actualResult, expectedResult),
          true,
        );
      });
      test(
          'Creates new bundles when next max data item count is smaller than number of data items passed',
          () async {
        final testItem1 = TestSizedItem(size: 5);
        final testItem2 = TestSizedItem(size: 1);
        final testItem3 = TestSizedItem(size: 1);
        final binPacker =
            NextFitBundlePacker(maxBundleSize: 20, maxDataItemCount: 1);
        final actualResult = await binPacker.packItems([
          testItem1,
          testItem2,
          testItem3,
        ]);
        final expectedResult = [
          [testItem1],
          [testItem2],
          [testItem3],
        ];
        printOnFailure(
            actualResult.map((e) => e.map((e) => e.size)).toString());
        expect(
          const DeepCollectionEquality().equals(actualResult, expectedResult),
          true,
        );
      });
    });
  });
}
