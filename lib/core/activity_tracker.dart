class ActivityTracker {
  bool _isToppingUp = false;
  bool _isSyncing = false;
  bool _isUploading = false;

  // getters
  bool get isToppingUp => _isToppingUp;
  bool get isSyncing => _isSyncing;
  bool get isUploading => _isUploading;

  // setters
  void setToppingUp(bool value) {
    _isToppingUp = value;
  }

  void setSyncing(bool value) {
    _isSyncing = value;
  }

  void setUploading(bool value) {
    _isUploading = value;
  }
}
