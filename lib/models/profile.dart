import 'package:moor/moor.dart';

class Profiles extends Table {
  TextColumn get id => text()();

  TextColumn get username => text()();

  BlobColumn get encryptedWallet => blob()();
  BlobColumn get walletSalt => blob()();

  @override
  Set<Column> get primaryKey => {id};
}
