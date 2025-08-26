import 'package:flutter/foundation.dart';

void ardriveIODebugPrint(String message) {
  if (kDebugMode) {
    print('[ardrive_io] $message');
  }
}
