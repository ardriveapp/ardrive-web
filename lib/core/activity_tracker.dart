import 'package:flutter/foundation.dart';

class ActivityTracker extends ChangeNotifier {
  bool _isToppingUp = false;
  bool _isShowingAnyDialog = false;
  // getters
  bool get isToppingUp => _isToppingUp;

  // setters
  void setToppingUp(bool value) {
    _isToppingUp = value;
  }

  void setShowingAnyDialog(bool value) {
    _isShowingAnyDialog = value;
    notifyListeners();
  }

  bool get isSyncAllowed {
    return !isToppingUp;
  }

  bool get isMultiSelectEnabled {
    return !_isShowingAnyDialog;
  }
}
