import 'package:ardrive/utils/logger.dart';

import 'bundle_packer.dart';
import 'sized_item.dart';

/// First-Fit-Decreasing (FFD) bin packing algorithm for bundling files.
///
/// This algorithm provides better space utilization than Next-Fit by:
/// 1. Sorting items by size (largest first)
/// 2. Trying to fit each item into the first bundle that has space
/// 3. Creating new bundles only when necessary
///
/// Typically achieves 10-20% better space utilization than Next-Fit,
/// meaning fewer bundles and lower upload costs.
///
/// Respects both size and count constraints:
/// - maxBundleSize: Maximum total bytes per bundle
/// - maxDataItemCount: Maximum number of items per bundle
class FirstFitDecreasingBundlePacker<T extends SizedItem>
    implements BundlePacker<T> {
  final int maxBundleSize;
  final int maxDataItemCount;

  FirstFitDecreasingBundlePacker({
    required this.maxBundleSize,
    required this.maxDataItemCount,
  });

  @override
  Future<List<List<T>>> packItems(List<T> items) async {
    if (items.isEmpty) {
      return [];
    }

    logger.i(
      'Packing ${items.length} items using First-Fit-Decreasing algorithm. '
      'Max bundle size: $maxBundleSize bytes, max items per bundle: $maxDataItemCount',
    );

    // Step 1: Sort items by size (largest first) for better packing
    final sortedItems = List<T>.from(items)
      ..sort((a, b) => b.size.compareTo(a.size));

    final bundles = <List<T>>[];
    final bundleSizes = <int>[];

    // Step 2: Pack each item using First-Fit strategy
    for (final item in sortedItems) {
      if (item.size > maxBundleSize) {
        throw Exception(
          'Item size (${item.size} bytes) exceeds max bundle size ($maxBundleSize bytes). '
          'This item cannot be bundled.',
        );
      }

      bool itemPlaced = false;

      // Try to fit item into first available bundle
      for (int i = 0; i < bundles.length; i++) {
        final currentBundle = bundles[i];
        final currentSize = bundleSizes[i];

        final wouldFitSize = currentSize + item.size <= maxBundleSize;
        final wouldFitCount = currentBundle.length < maxDataItemCount;

        if (wouldFitSize && wouldFitCount) {
          // Item fits! Add to this bundle
          currentBundle.add(item);
          bundleSizes[i] = currentSize + item.size;
          itemPlaced = true;
          break;
        }
      }

      // If item didn't fit anywhere, create new bundle
      if (!itemPlaced) {
        bundles.add([item]);
        bundleSizes.add(item.size);
      }
    }

    logger.i(
      'Packing complete: ${items.length} items packed into ${bundles.length} bundles. '
      'Average bundle utilization: ${_calculateUtilization(bundleSizes)}%',
    );

    // Log bundle sizes for debugging
    for (int i = 0; i < bundles.length; i++) {
      logger.d(
        'Bundle $i: ${bundles[i].length} items, ${bundleSizes[i]} bytes '
        '(${(bundleSizes[i] / maxBundleSize * 100).toStringAsFixed(1)}% full)',
      );
    }

    return bundles;
  }

  /// Calculates average bundle space utilization as a percentage
  int _calculateUtilization(List<int> bundleSizes) {
    if (bundleSizes.isEmpty) return 0;

    final totalUsed = bundleSizes.reduce((a, b) => a + b);
    final totalAvailable = bundleSizes.length * maxBundleSize;

    return ((totalUsed / totalAvailable) * 100).round();
  }
}
