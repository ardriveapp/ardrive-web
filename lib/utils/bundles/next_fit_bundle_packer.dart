import 'package:ardrive/utils/logger.dart';

import 'bundle_packer.dart';
import 'sized_item.dart';

class NextFitBundlePacker<T extends SizedItem> implements BundlePacker<T> {
  int maxBundleSize;
  int maxDataItemCount;
  NextFitBundlePacker({
    required this.maxBundleSize,
    required this.maxDataItemCount,
  });

  @override
  Future<List<List<T>>> packItems(List<T> items) async {
    logger.i(
        'Creating bundle handles from data item handles with a max number of files of $maxDataItemCount');
    final bundles = <List<T>>[];
    var bundleItems = <T>[];
    // Walk through all items
    for (final item in items) {
      if (item.size > maxBundleSize) {
        throw Exception('Item exceeds max packing size');
      }

      // Get size of current bundle
      final totalBundleSize = bundleItems.isNotEmpty
          ? bundleItems
              .map((e) => e.size)
              .reduce((value, element) => value + element)
          : 0;

      // Add items to current bundle if it will fit, new bundle otherwise
      final shouldAddToBundle = totalBundleSize + item.size <= maxBundleSize &&
          bundleItems.length < maxDataItemCount;
      if (!shouldAddToBundle) {
        // Finish current bundle and prepare to start new bundle
        bundles.add(bundleItems);
        bundleItems = [];
      }
      bundleItems.add(item);
    }
    if (bundleItems.isNotEmpty) {
      bundles.add(bundleItems);
    }
    return bundles;
  }
}
