enum PlausibleCustomEvent {
  appLoaded,
  uploadFile,
  uploadFolder,
  uploadReview,
  newButton,
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
      case PlausibleCustomEvent.newButton:
        return 'New Button';
      default:
        return 'Unknown';
    }
  }
}
