enum PlausibleCustomEvent {
  appLoaded,
  newButton,
  login,
  uploadReview,
  uploadConfirm,
  uploadSuccess,
  uploadFailure,
}

extension PlausibleCustomEventNames on PlausibleCustomEvent {
  String get name {
    switch (this) {
      case PlausibleCustomEvent.appLoaded:
        return 'App Loaded';
      case PlausibleCustomEvent.newButton:
        return 'New Button';
      case PlausibleCustomEvent.login:
        return 'Login';
      case PlausibleCustomEvent.uploadReview:
        return 'Upload Review';
      case PlausibleCustomEvent.uploadConfirm:
        return 'Upload Confirm';
      case PlausibleCustomEvent.uploadSuccess:
        return 'Upload Success';
      case PlausibleCustomEvent.uploadFailure:
        return 'Upload Failure';
    }
  }
}
