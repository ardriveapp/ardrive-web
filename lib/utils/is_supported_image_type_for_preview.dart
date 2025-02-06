import 'package:ardrive/utils/constants.dart';

/// Checks if the given content type is a supported image type for file preview
bool isSupportedImageTypeForPreview(String? contentType) {
  if (contentType == null) return false;

  return supportedImageTypesInFilePreview.contains(contentType);
}
