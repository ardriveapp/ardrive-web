enum FileSizeUnit {
  bytes,
  kilobytes,
  megabytes,
  gigabytes,
}

extension FileSizeUnitExtension on FileSizeUnit {
  String get name {
    switch (this) {
      case FileSizeUnit.bytes:
        return 'bytes';
      case FileSizeUnit.kilobytes:
        return 'KB';
      case FileSizeUnit.megabytes:
        return 'MB';
      case FileSizeUnit.gigabytes:
        return 'GB';
      default:
        throw Exception('Unknown file size unit: $this');
    }
  }
}
