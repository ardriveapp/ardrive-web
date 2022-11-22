abstract class RevisionAction {
  static const create = 'create';
  static const uploadNewVersion = 'upload-new-version';
  static const rename = 'rename';
  static const move = 'move';
}

abstract class TransactionStatus {
  static const pending = 'pending';
  static const confirmed = 'confirmed';
  static const failed = 'failed';
}

enum SyncType { normal, deep }
