enum PlausibleCustomEvent {
  appLoaded,
  uploadReview,
  uploadConfirm,
  uploadSuccess,
  uploadFailure,
  newButton,
}

extension PlausibleCustomEventNames on PlausibleCustomEvent {
  String get name {
    switch (this) {
      case PlausibleCustomEvent.appLoaded:
        return 'App Loaded';
      case PlausibleCustomEvent.uploadReview:
        return 'Upload Review';
      case PlausibleCustomEvent.uploadConfirm:
        return 'Upload Confirm';
      case PlausibleCustomEvent.uploadSuccess:
        return 'Upload Success';
      case PlausibleCustomEvent.uploadFailure:
        return 'Upload Failure';
      case PlausibleCustomEvent.newButton:
        return 'New Button';
      default:
        return 'Unknown';
    }
  }
}
