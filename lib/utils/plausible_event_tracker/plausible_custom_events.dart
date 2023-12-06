enum PlausibleCustomEvent {
  appLoaded,
  uploadFile,
  uploadFolder,
  uploadReview,
}

extension PlausibleCustomEventNames on PlausibleCustomEvent {
  String get name {
    switch (this) {
      case PlausibleCustomEvent.appLoaded:
        return 'App Loaded';
      case PlausibleCustomEvent.uploadFile:
        return 'Upload File';
      case PlausibleCustomEvent.uploadFolder:
        return 'Upload Folder';
      case PlausibleCustomEvent.uploadReview:
        return 'Upload Review';
      default:
        return 'Unknown';
    }
  }
}
