enum PlausibleCustomEvent {
  appLoaded,
  driveCreation,
  folderCreation,
  newButton,
  login,
  resync,
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
      case PlausibleCustomEvent.driveCreation:
        return 'Drive Creation';
      case PlausibleCustomEvent.folderCreation:
        return 'Folder Creation';
      case PlausibleCustomEvent.newButton:
        return 'New Button';
      case PlausibleCustomEvent.login:
        return 'Login';
      case PlausibleCustomEvent.resync:
        return 'Resync';
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
