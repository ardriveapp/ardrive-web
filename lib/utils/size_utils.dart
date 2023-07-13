import 'package:ardrive/blocs/upload/upload_handles/bundle_upload_handle.dart';
import 'package:ardrive/blocs/upload/upload_handles/file_v2_upload_handle.dart';

class SizeUtils {
  final _bundleSizeCalculator = BundleSizeCalculator();
  final _v2SizeCalculator = V2SizeCalculator();

  Future<int> getSizeOfAllBundles(
      List<BundleUploadHandle> bundleUploadHandles) async {
    return _bundleSizeCalculator.getSizeOfAllBundles(bundleUploadHandles);
  }

  Future<int> getSizeOfAllV2Files(
      Map<String, FileV2UploadHandle> fileV2UploadHandles) async {
    return _v2SizeCalculator.getSizeOfAllV2Files(fileV2UploadHandles);
  }
}

class BundleSizeCalculator {
  Future<int> getSizeOfAllBundles(
      List<BundleUploadHandle> bundleUploadHandles) async {
    var totalSize = 0;

    for (var bundle in bundleUploadHandles) {
      totalSize += await bundle.computeBundleSize();
    }

    return totalSize;
  }
}

class V2SizeCalculator {
  Future<int> getSizeOfAllV2Files(
      Map<String, FileV2UploadHandle> fileV2UploadHandles) async {
    var totalSize = 0;

    for (var file in fileV2UploadHandles.values) {
      totalSize += file.getFileDataSize();
      totalSize += file.getMetadataJSONSize();
    }

    return totalSize;
  }
}
