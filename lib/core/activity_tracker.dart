class ActivityTracker {
  bool _isToppingUp = false;
  // getters
  bool get isToppingUp => _isToppingUp;

  // setters
  void setToppingUp(bool value) {
    _isToppingUp = value;
  }

  bool get isSyncAllowed {
    return !isToppingUp;
  }
}
