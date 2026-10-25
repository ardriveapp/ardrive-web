import 'package:flutter/foundation.dart';

class ActivityTracker extends ChangeNotifier {
  bool _isToppingUp = false;

  /// How many dialogs are open. A count, not a flag: a dialog opened from
  /// another one, such as a discard confirmation, closed first and cleared a
  /// flag while the dialog under it was still open.
  int _openDialogs = 0;
  bool _isUploading = false;
  bool _isSharingFilesFromExternalApp = false;
  bool _isVerifyingSharingFilesFromExternalApp = true;
  bool _isBulkImporting = false;

  // getters
  bool get isToppingUp => _isToppingUp;

  bool get isSyncAllowed {
    return !isToppingUp;
  }

  bool get isMultiSelectEnabled {
    return _openDialogs == 0;
  }

  bool get isUploading => _isUploading;

  bool get isSharingFilesFromExternalApp => _isSharingFilesFromExternalApp;

  bool get isVerifyingSharingFilesFromExternalApp =>
      _isVerifyingSharingFilesFromExternalApp;

  bool get isBulkImporting => _isBulkImporting;

  // setters
  void setUploading(bool value) {
    _isUploading = value;
    notifyListeners();
  }

  void setToppingUp(bool value) {
    _isToppingUp = value;
  }

  /// Records a dialog opening (true) or closing (false). Calls come in
  /// pairs, one of each per dialog.
  void setShowingAnyDialog(bool value) {
    _openDialogs =
        value ? _openDialogs + 1 : (_openDialogs - 1).clamp(0, _openDialogs);
    notifyListeners();
  }

  void setSharingFilesFromExternalApp(bool value) {
    _isSharingFilesFromExternalApp = value;
    notifyListeners();
  }

  void setVerifyingSharingFilesFromExternalApp(bool value) {
    _isVerifyingSharingFilesFromExternalApp = value;
    notifyListeners();
  }

  void setBulkImporting(bool value) {
    _isBulkImporting = value;
    notifyListeners();
  }
}
