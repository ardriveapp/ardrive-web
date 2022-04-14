import 'package:ardrive/utils/bundles/sized_item.dart';

abstract class UploadHandle implements SizedItem {
  /// The size of the file before it was encoded/encrypted for upload.
  @override
  int get size;

  /// The size of the file that has been uploaded, not accounting for the file encoding/encryption overhead.
  int get uploadedSize => (size * uploadProgress).round();

  double uploadProgress = 0;
}
