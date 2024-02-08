abstract class RevisionAction {
  static const create = 'create';
  static const uploadNewVersion = 'upload-new-version';
  static const rename = 'rename';
  static const move = 'move';
  static const hide = 'hide';
  static const unhide = 'unhide';
}

abstract class TransactionStatus {
  static const pending = 'pending';
  static const confirmed = 'confirmed';
  static const failed = 'failed';
}

enum SyncType { normal, deep }
