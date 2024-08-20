import 'package:ardrive_utils/ardrive_utils.dart';

/// Check if the Ario SDK is supported on the current platform
bool isArioSDKSupportedOnPlatform() {
  return AppPlatform.isWeb();
}
