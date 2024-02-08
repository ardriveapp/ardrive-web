// GENERATED CODE, DO NOT EDIT BY HAND.
// ignore_for_file: type=lint
//@dart=2.12
import 'package:drift/drift.dart';

class SnapshotEntries extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  SnapshotEntries(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> driveId = GeneratedColumn<String>(
      'driveId', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<int> blockStart = GeneratedColumn<int>(
      'blockStart', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<int> blockEnd = GeneratedColumn<int>(
      'blockEnd', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<int> dataStart = GeneratedColumn<int>(
      'dataStart', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<int> dataEnd = GeneratedColumn<int>(
      'dataEnd', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> txId = GeneratedColumn<String>(
      'txId', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<DateTime> dateCreated = GeneratedColumn<DateTime>(
      'dateCreated', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL DEFAULT (strftime(\'%s\', \'now\'))',
      defaultValue: const CustomExpression('strftime(\'%s\', \'now\')'));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        driveId,
        blockStart,
        blockEnd,
        dataStart,
        dataEnd,
        txId,
        dateCreated
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'snapshot_entries';
  @override
  Set<GeneratedColumn> get $primaryKey => {id, driveId};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  SnapshotEntries createAlias(String alias) {
    return SnapshotEntries(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const ['PRIMARY KEY(id, driveId)'];
  @override
  bool get dontWriteConstraints => true;
}

class Profiles extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Profiles(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL PRIMARY KEY');
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
      'username', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<Uint8List> encryptedWallet =
      GeneratedColumn<Uint8List>('encryptedWallet', aliasedName, false,
          type: DriftSqlType.blob,
          requiredDuringInsert: true,
          $customConstraints: 'NOT NULL');
  late final GeneratedColumn<Uint8List> keySalt = GeneratedColumn<Uint8List>(
      'keySalt', aliasedName, false,
      type: DriftSqlType.blob,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> walletPublicKey = GeneratedColumn<String>(
      'walletPublicKey', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<Uint8List> encryptedPublicKey =
      GeneratedColumn<Uint8List>('encryptedPublicKey', aliasedName, false,
          type: DriftSqlType.blob,
          requiredDuringInsert: true,
          $customConstraints: 'NOT NULL');
  late final GeneratedColumn<int> profileType = GeneratedColumn<int>(
      'profileType', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  @override
  List<GeneratedColumn> get $columns => [
        id,
        username,
        encryptedWallet,
        keySalt,
        walletPublicKey,
        encryptedPublicKey,
        profileType
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profiles';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  Profiles createAlias(String alias) {
    return Profiles(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class NetworkTransactions extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  NetworkTransactions(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL PRIMARY KEY');
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL DEFAULT \'pending\'',
      defaultValue: const CustomExpression('\'pending\''));
  late final GeneratedColumn<DateTime> dateCreated = GeneratedColumn<DateTime>(
      'dateCreated', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL DEFAULT (strftime(\'%s\', \'now\'))',
      defaultValue: const CustomExpression('strftime(\'%s\', \'now\')'));
  late final GeneratedColumn<DateTime> transactionDateCreated =
      GeneratedColumn<DateTime>('transactionDateCreated', aliasedName, true,
          type: DriftSqlType.dateTime,
          requiredDuringInsert: false,
          $customConstraints: '');
  @override
  List<GeneratedColumn> get $columns =>
      [id, status, dateCreated, transactionDateCreated];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'network_transactions';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  NetworkTransactions createAlias(String alias) {
    return NetworkTransactions(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class FolderRevisions extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  FolderRevisions(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> folderId = GeneratedColumn<String>(
      'folderId', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> driveId = GeneratedColumn<String>(
      'driveId', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> parentFolderId = GeneratedColumn<String>(
      'parentFolderId', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: '');
  late final GeneratedColumn<String> metadataTxId = GeneratedColumn<String>(
      'metadataTxId', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<DateTime> dateCreated = GeneratedColumn<DateTime>(
      'dateCreated', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL DEFAULT (strftime(\'%s\', \'now\'))',
      defaultValue: const CustomExpression('strftime(\'%s\', \'now\')'));
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
      'action', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> customJsonMetadata =
      GeneratedColumn<String>('customJsonMetadata', aliasedName, true,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          $customConstraints: '');
  late final GeneratedColumn<String> customGQLTags = GeneratedColumn<String>(
      'customGQLTags', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: '');
  @override
  List<GeneratedColumn> get $columns => [
        folderId,
        driveId,
        name,
        parentFolderId,
        metadataTxId,
        dateCreated,
        action,
        customJsonMetadata,
        customGQLTags
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'folder_revisions';
  @override
  Set<GeneratedColumn> get $primaryKey => {folderId, driveId, dateCreated};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  FolderRevisions createAlias(String alias) {
    return FolderRevisions(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
        'PRIMARY KEY(folderId, driveId, dateCreated)',
        'FOREIGN KEY(metadataTxId)REFERENCES network_transactions(id)'
      ];
  @override
  bool get dontWriteConstraints => true;
}

class FolderEntries extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  FolderEntries(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> driveId = GeneratedColumn<String>(
      'driveId', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> parentFolderId = GeneratedColumn<String>(
      'parentFolderId', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: '');
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
      'path', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<DateTime> dateCreated = GeneratedColumn<DateTime>(
      'dateCreated', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL DEFAULT (strftime(\'%s\', \'now\'))',
      defaultValue: const CustomExpression('strftime(\'%s\', \'now\')'));
  late final GeneratedColumn<DateTime> lastUpdated = GeneratedColumn<DateTime>(
      'lastUpdated', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL DEFAULT (strftime(\'%s\', \'now\'))',
      defaultValue: const CustomExpression('strftime(\'%s\', \'now\')'));
  late final GeneratedColumn<bool> isGhost = GeneratedColumn<bool>(
      'isGhost', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL DEFAULT FALSE',
      defaultValue: const CustomExpression('FALSE'));
  late final GeneratedColumn<String> customJsonMetadata =
      GeneratedColumn<String>('customJsonMetadata', aliasedName, true,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          $customConstraints: '');
  late final GeneratedColumn<String> customGQLTags = GeneratedColumn<String>(
      'customGQLTags', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: '');
  @override
  List<GeneratedColumn> get $columns => [
        id,
        driveId,
        name,
        parentFolderId,
        path,
        dateCreated,
        lastUpdated,
        isGhost,
        customJsonMetadata,
        customGQLTags
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'folder_entries';
  @override
  Set<GeneratedColumn> get $primaryKey => {id, driveId};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  FolderEntries createAlias(String alias) {
    return FolderEntries(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const ['PRIMARY KEY(id, driveId)'];
  @override
  bool get dontWriteConstraints => true;
}

class FileRevisions extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  FileRevisions(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> fileId = GeneratedColumn<String>(
      'fileId', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> driveId = GeneratedColumn<String>(
      'driveId', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> parentFolderId = GeneratedColumn<String>(
      'parentFolderId', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
      'size', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<DateTime> lastModifiedDate =
      GeneratedColumn<DateTime>('lastModifiedDate', aliasedName, false,
          type: DriftSqlType.dateTime,
          requiredDuringInsert: true,
          $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> dataContentType = GeneratedColumn<String>(
      'dataContentType', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: '');
  late final GeneratedColumn<String> metadataTxId = GeneratedColumn<String>(
      'metadataTxId', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> dataTxId = GeneratedColumn<String>(
      'dataTxId', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> bundledIn = GeneratedColumn<String>(
      'bundledIn', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: '');
  late final GeneratedColumn<DateTime> dateCreated = GeneratedColumn<DateTime>(
      'dateCreated', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL DEFAULT (strftime(\'%s\', \'now\'))',
      defaultValue: const CustomExpression('strftime(\'%s\', \'now\')'));
  late final GeneratedColumn<String> customJsonMetadata =
      GeneratedColumn<String>('customJsonMetadata', aliasedName, true,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          $customConstraints: '');
  late final GeneratedColumn<String> customGQLTags = GeneratedColumn<String>(
      'customGQLTags', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: '');
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
      'action', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> pinnedDataOwnerAddress =
      GeneratedColumn<String>('pinnedDataOwnerAddress', aliasedName, true,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          $customConstraints: '');
  @override
  List<GeneratedColumn> get $columns => [
        fileId,
        driveId,
        name,
        parentFolderId,
        size,
        lastModifiedDate,
        dataContentType,
        metadataTxId,
        dataTxId,
        bundledIn,
        dateCreated,
        customJsonMetadata,
        customGQLTags,
        action,
        pinnedDataOwnerAddress
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'file_revisions';
  @override
  Set<GeneratedColumn> get $primaryKey => {fileId, driveId, dateCreated};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  FileRevisions createAlias(String alias) {
    return FileRevisions(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
        'PRIMARY KEY(fileId, driveId, dateCreated)',
        'FOREIGN KEY(metadataTxId)REFERENCES network_transactions(id)',
        'FOREIGN KEY(dataTxId)REFERENCES network_transactions(id)'
      ];
  @override
  bool get dontWriteConstraints => true;
}

class FileEntries extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  FileEntries(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> driveId = GeneratedColumn<String>(
      'driveId', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> parentFolderId = GeneratedColumn<String>(
      'parentFolderId', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
      'path', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
      'size', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<DateTime> lastModifiedDate =
      GeneratedColumn<DateTime>('lastModifiedDate', aliasedName, false,
          type: DriftSqlType.dateTime,
          requiredDuringInsert: true,
          $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> dataContentType = GeneratedColumn<String>(
      'dataContentType', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: '');
  late final GeneratedColumn<String> dataTxId = GeneratedColumn<String>(
      'dataTxId', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> bundledIn = GeneratedColumn<String>(
      'bundledIn', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: '');
  late final GeneratedColumn<String> pinnedDataOwnerAddress =
      GeneratedColumn<String>('pinnedDataOwnerAddress', aliasedName, true,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          $customConstraints: '');
  late final GeneratedColumn<String> customJsonMetadata =
      GeneratedColumn<String>('customJsonMetadata', aliasedName, true,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          $customConstraints: '');
  late final GeneratedColumn<String> customGQLTags = GeneratedColumn<String>(
      'customGQLTags', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: '');
  late final GeneratedColumn<DateTime> dateCreated = GeneratedColumn<DateTime>(
      'dateCreated', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL DEFAULT (strftime(\'%s\', \'now\'))',
      defaultValue: const CustomExpression('strftime(\'%s\', \'now\')'));
  late final GeneratedColumn<DateTime> lastUpdated = GeneratedColumn<DateTime>(
      'lastUpdated', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL DEFAULT (strftime(\'%s\', \'now\'))',
      defaultValue: const CustomExpression('strftime(\'%s\', \'now\')'));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        driveId,
        name,
        parentFolderId,
        path,
        size,
        lastModifiedDate,
        dataContentType,
        dataTxId,
        bundledIn,
        pinnedDataOwnerAddress,
        customJsonMetadata,
        customGQLTags,
        dateCreated,
        lastUpdated
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'file_entries';
  @override
  Set<GeneratedColumn> get $primaryKey => {id, driveId};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  FileEntries createAlias(String alias) {
    return FileEntries(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const ['PRIMARY KEY(id, driveId)'];
  @override
  bool get dontWriteConstraints => true;
}

class Drives extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Drives(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL PRIMARY KEY');
  late final GeneratedColumn<String> rootFolderId = GeneratedColumn<String>(
      'rootFolderId', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> ownerAddress = GeneratedColumn<String>(
      'ownerAddress', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> syncCursor = GeneratedColumn<String>(
      'syncCursor', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: '');
  late final GeneratedColumn<int> lastBlockHeight = GeneratedColumn<int>(
      'lastBlockHeight', aliasedName, true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints: 'DEFAULT 0',
      defaultValue: const CustomExpression('0'));
  late final GeneratedColumn<String> privacy = GeneratedColumn<String>(
      'privacy', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<Uint8List> encryptedKey =
      GeneratedColumn<Uint8List>('encryptedKey', aliasedName, true,
          type: DriftSqlType.blob,
          requiredDuringInsert: false,
          $customConstraints: '');
  late final GeneratedColumn<Uint8List> keyEncryptionIv =
      GeneratedColumn<Uint8List>('keyEncryptionIv', aliasedName, true,
          type: DriftSqlType.blob,
          requiredDuringInsert: false,
          $customConstraints: '');
  late final GeneratedColumn<String> bundledIn = GeneratedColumn<String>(
      'bundledIn', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: '');
  late final GeneratedColumn<String> customJsonMetadata =
      GeneratedColumn<String>('customJsonMetadata', aliasedName, true,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          $customConstraints: '');
  late final GeneratedColumn<String> customGQLTags = GeneratedColumn<String>(
      'customGQLTags', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: '');
  late final GeneratedColumn<DateTime> dateCreated = GeneratedColumn<DateTime>(
      'dateCreated', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL DEFAULT (strftime(\'%s\', \'now\'))',
      defaultValue: const CustomExpression('strftime(\'%s\', \'now\')'));
  late final GeneratedColumn<DateTime> lastUpdated = GeneratedColumn<DateTime>(
      'lastUpdated', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL DEFAULT (strftime(\'%s\', \'now\'))',
      defaultValue: const CustomExpression('strftime(\'%s\', \'now\')'));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        rootFolderId,
        ownerAddress,
        name,
        syncCursor,
        lastBlockHeight,
        privacy,
        encryptedKey,
        keyEncryptionIv,
        bundledIn,
        customJsonMetadata,
        customGQLTags,
        dateCreated,
        lastUpdated
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'drives';
  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  Drives createAlias(String alias) {
    return Drives(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class DriveRevisions extends Table with TableInfo {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  DriveRevisions(this.attachedDatabase, [this._alias]);
  late final GeneratedColumn<String> driveId = GeneratedColumn<String>(
      'driveId', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> rootFolderId = GeneratedColumn<String>(
      'rootFolderId', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> ownerAddress = GeneratedColumn<String>(
      'ownerAddress', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> privacy = GeneratedColumn<String>(
      'privacy', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> metadataTxId = GeneratedColumn<String>(
      'metadataTxId', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<DateTime> dateCreated = GeneratedColumn<DateTime>(
      'dateCreated', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL DEFAULT (strftime(\'%s\', \'now\'))',
      defaultValue: const CustomExpression('strftime(\'%s\', \'now\')'));
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
      'action', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  late final GeneratedColumn<String> bundledIn = GeneratedColumn<String>(
      'bundledIn', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: '');
  late final GeneratedColumn<String> customJsonMetadata =
      GeneratedColumn<String>('customJsonMetadata', aliasedName, true,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          $customConstraints: '');
  late final GeneratedColumn<String> customGQLTags = GeneratedColumn<String>(
      'customGQLTags', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: '');
  @override
  List<GeneratedColumn> get $columns => [
        driveId,
        rootFolderId,
        ownerAddress,
        name,
        privacy,
        metadataTxId,
        dateCreated,
        action,
        bundledIn,
        customJsonMetadata,
        customGQLTags
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'drive_revisions';
  @override
  Set<GeneratedColumn> get $primaryKey => {driveId, dateCreated};
  @override
  Never map(Map<String, dynamic> data, {String? tablePrefix}) {
    throw UnsupportedError('TableInfo.map in schema verification code');
  }

  @override
  DriveRevisions createAlias(String alias) {
    return DriveRevisions(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
        'PRIMARY KEY(driveId, dateCreated)',
        'FOREIGN KEY(metadataTxId)REFERENCES network_transactions(id)'
      ];
  @override
  bool get dontWriteConstraints => true;
}

class DatabaseAtV17 extends GeneratedDatabase {
  DatabaseAtV17(QueryExecutor e) : super(e);
  late final SnapshotEntries snapshotEntries = SnapshotEntries(this);
  late final Profiles profiles = Profiles(this);
  late final NetworkTransactions networkTransactions =
      NetworkTransactions(this);
  late final FolderRevisions folderRevisions = FolderRevisions(this);
  late final FolderEntries folderEntries = FolderEntries(this);
  late final FileRevisions fileRevisions = FileRevisions(this);
  late final FileEntries fileEntries = FileEntries(this);
  late final Drives drives = Drives(this);
  late final DriveRevisions driveRevisions = DriveRevisions(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        snapshotEntries,
        profiles,
        networkTransactions,
        folderRevisions,
        folderEntries,
        fileRevisions,
        fileEntries,
        drives,
        driveRevisions
      ];
  @override
  int get schemaVersion => 17;
}
