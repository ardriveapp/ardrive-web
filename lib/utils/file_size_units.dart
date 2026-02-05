enum FileSizeUnit {
  bytes,
  kilobytes,
  megabytes,
  gigabytes,
}

extension FileSizeUnitExtension on FileSizeUnit {
  /// Returns the abbreviated display name for the unit (e.g., "GB", "MB").
  /// Note: This was renamed from `name` to `abbreviation` because Dart's
  /// built-in enum `.name` property shadows extension getters.
  String get abbreviation {
    switch (this) {
      case FileSizeUnit.bytes:
        return 'bytes';
      case FileSizeUnit.kilobytes:
        return 'KB';
      case FileSizeUnit.megabytes:
        return 'MB';
      case FileSizeUnit.gigabytes:
        return 'GB';
    }
  }
}
