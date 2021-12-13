import 'bundle_packer.dart';

class NextFitBundlePacker<T extends SizedItem> implements BundlePacker<T> {
  int maxBundleSize;
  NextFitBundlePacker({
    required this.maxBundleSize,
  });

  @override
  Future<List<List<T>>> packItems(List<T> items) async {
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
      final shouldAddToBundle = totalBundleSize + item.size <= maxBundleSize;
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
