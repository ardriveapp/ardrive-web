abstract class UploadHandle {
  
  BigInt? get cost;

  /// The size of the file before it was encoded/encrypted for upload.
  int? get size;

  /// The size of the file that has been uploaded, not accounting for the file encoding/encryption overhead.
  int get uploadedSize => (size! * uploadProgress).round();

  double uploadProgress = 0;
}
